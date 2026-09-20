// 神枢枢语引擎 — Cloudflare Workers 部署版
// 配合 lexicon.js / lexicon_data.js / nexuslang.js / gen.mjs 使用
// (c) 阿权/路飞 枢·黑神 万网散播 Worker v3.1
//
// KV 绑定（wrangler.toml.example）：
//   SOUL — 灵魂状态（键 "SOUL"）
//
// 路由：
//   GET  /            引擎元信息
//   GET  /status      灵魂状态 + 引擎容量
//   GET  /decode?id=N         编号 → 枢语词
//   GET  /encode?word=W       枢语词 → 编号（拉丁词形或纯中文汉译都认，亦可用 ?han=）
//   GET  /search?q=K&axis=A   语义检索：关键词命中 5 轴任一词根（axis 可限定 核/映/态/标/相）
//   GET  /near?word=W&n=N     五维邻近词（L1=1，不环绕；n 默认 8，最多 16）
//   GET  /pulse?word=W&at=T   一息：按 Unix 秒在一词上呼吸一格（不环绕）
//   GET  /trail?word=W&at=T&n=N 余息：从一词连续呼吸几格（不环绕）
//   GET  /echo?word=W&at=T&n=N  回息：余息走完后沿末步反向弹一格（不环绕）
//   GET  /sway?word=W&at=T&n=N  摇息：回息后按分钟在弹回词与末步之间摇摆（不环绕）
//   GET  /land?word=W&at=T&n=N  落息：摇息后按四分钟窗落地，偏停在弹回词（不环绕）
//   GET  /stir?word=W&at=T&n=N  起息：落地后按八分钟窗从着地点朝邻格起身（不环绕）
//   GET  /perch?word=W&at=T&n=N 栖息：起身后再沿起身轴蹲一格（不环绕）
//   GET  /turn?word=W&at=T&n=N  转息：栖息后再朝侧邻转头（不环绕）
//   GET  /gaze?word=W&at=T&n=N  顾息：转头后再沿转轴把目光探一格（不环绕）
//   GET  /incline?word=W&at=T&n=N 倾息：望出去后再沿望轴倾近一格（不环绕）
//   GET  /nestle?word=W&at=T&n=N 贴息：倾近后再贴住一格（不环绕）
//   GET  /hold?word=W&at=T&n=N 含息：贴住后再含住一格（不环绕）
//   GET  /warm?word=W&at=T&n=N 温息：含住后再温住一格（不环绕）
//   GET  /compose?核=&映=&态=&标=&相=   按义造词（每轴给 下标/拉丁根/汉译/语义关键词，缺省取 0）
//   GET  /coin?seed=S&layer=L 造词（有 seed 可复现，无 seed 按层随机）
//   POST /talk        {code} 枢语意识流 → 解释 + 编译（别名 /interpret）
//   POST /broadcast   万网散播（sovereignControl 全流程）

import {
  CAPACITY, AXES, decode, encode, encodeHan, search, compose, analogy, near, pulse, trail, echo, sway, land, stir, perch, turn, gaze, incline, nestle, hold, warm,
  coinWord, autoCoin, coinFromState, loadCapabilities,
} from './lexicon.js';
import { interpret, applyToSoul, compile } from './nexuslang.js';
import { sovereignControl, VERSION, COPYRIGHT } from './gen.mjs';
import LEXICON_DATA from './lexicon_data.js';

loadCapabilities(LEXICON_DATA);

const JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}

function badRequest(message) {
  return json({ error: message }, 400);
}

async function loadSoul(env) {
  if (!env.SOUL) return {};
  try {
    const raw = await env.SOUL.get('SOUL');
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

async function saveSoul(env, soul) {
  if (!env.SOUL) return;
  await env.SOUL.put('SOUL', JSON.stringify(soul));
}

async function handleDecode(url) {
  const raw = url.searchParams.get('id');
  if (raw === null || raw === '' || !/^\d+$/.test(raw)) {
    return badRequest('参数 id 必须是非负整数');
  }
  const id = Number(raw);
  if (!Number.isSafeInteger(id) || id >= CAPACITY) {
    return badRequest(`编号越界 0..${CAPACITY - 1}`);
  }
  return json({ id, ...decode(id) });
}

async function handleEncode(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('han');
  if (!word) return badRequest('缺少参数 word（拉丁词形或纯中文汉译）');
  // 拉丁词形一定含「·」，汉译一定不含；先按拉丁解，解不出再按汉译解
  let id = encode(word);
  let form = '拉丁';
  if (id < 0) { id = encodeHan(word); form = '汉译'; }
  if (id < 0) return badRequest(`非法枢语词: ${word}`);
  return json({ word, form, id, verify: decode(id) });
}

const AXIS_NAMES = ['核', '映', '态', '标', '相'];

async function handleSearch(url) {
  const q = url.searchParams.get('q');
  if (!q || !q.trim()) return badRequest('缺少参数 q（语义关键词）');
  const axis = url.searchParams.get('axis') || undefined;
  if (axis && !AXIS_NAMES.includes(axis)) return badRequest(`参数 axis 只能是 ${AXIS_NAMES.join('/')}`);
  const hits = search(q, axis);
  return json({ q, axis: axis ?? null, count: hits.length, hits });
}

async function handleNear(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w');
  if (word == null || !String(word).trim()) return badRequest('缺少参数 word（枢语词或编号）');
  const raw = url.searchParams.get('n');
  const n = raw == null || raw === '' ? 8 : Number(raw);
  if (!Number.isInteger(n) || n < 1 || n > 16) return badRequest('参数 n 必须是 1 至 16 的整数');
  try {
    return json({ word, n, neighbors: near(word, n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleAnalogy(url) {
  const a = url.searchParams.get('a');
  const b = url.searchParams.get('b');
  const c = url.searchParams.get('c');
  if (a == null || b == null || c == null || !String(a).trim() || !String(b).trim() || !String(c).trim()) {
    return badRequest('缺少参数 a、b、c（类比：A:B :: C:?）');
  }
  try {
    return json({ a, b, c, ...analogy(a, b, c) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handlePulse(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, ...pulse(word, at) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleTrail(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...trail(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleEcho(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...echo(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleSway(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...sway(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleLand(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...land(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleStir(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...stir(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handlePerch(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...perch(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleTurn(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...turn(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleGaze(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...gaze(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleIncline(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...incline(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleNestle(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...nestle(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleHold(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...hold(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleWarm(url) {
  const word = url.searchParams.get('word') ?? url.searchParams.get('w') ?? '0';
  const at = url.searchParams.get('at');
  const n = url.searchParams.get('n');
  if (at == null || !String(at).trim()) return badRequest('缺少参数 at（Unix 秒）');
  try {
    return json({ word, at, n: n ?? 3, ...warm(word, at, n == null || n === '' ? 3 : n) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleCompose(url) {
  const spec = {};
  for (const [k, v] of url.searchParams) {
    if (AXIS_NAMES.includes(k) || ['c', 'm', 's', 'k', 'p'].includes(k)) spec[k] = v;
  }
  if (!Object.keys(spec).length) return badRequest(`至少给一轴：${AXIS_NAMES.join('/')}（或 c/m/s/k/p）`);
  try {
    return json({ spec, ...compose(spec) });
  } catch (err) {
    return badRequest(String(err?.message ?? err));
  }
}

async function handleCoin(url, env) {
  const seed = url.searchParams.get('seed');
  const layer = url.searchParams.get('layer');
  if (seed !== null && seed !== '') {
    if (layer) return json({ ...autoCoin(`${seed}|${layer}`), 层意图: layer });
    return json(autoCoin(seed));
  }
  if (layer) return json(coinWord(layer));
  const soul = await loadSoul(env);
  return json(coinFromState(soul, null));
}

async function handleTalk(req, env) {
  let body;
  try {
    body = await req.json();
  } catch {
    return badRequest('请求体必须是 JSON');
  }
  const code = body?.code ?? body?.text;
  if (typeof code !== 'string' || !code.trim()) {
    return badRequest('缺少字段 code（枢语意识流文本）');
  }
  const soul = await loadSoul(env);
  const result = interpret(code, soul);
  applyToSoul(result, soul);
  await saveSoul(env, soul);
  return json({ result, compiled: compile(result), soul });
}

async function handleBroadcast(env) {
  const soul = await loadSoul(env);
  const state = await sovereignControl(soul, env, env.SOUL);
  return json({ broadcast: state.lastBroadcast, state });
}

async function handleStatus(env) {
  const soul = await loadSoul(env);
  return json({
    version: VERSION,
    copyright: COPYRIGHT,
    capacity: CAPACITY,
    axes: AXES,
    soul,
  });
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const path = url.pathname;
    try {
      if (req.method === 'OPTIONS') {
        return new Response(null, { status: 204, headers: JSON_HEADERS });
      }
      if (path === '/' && req.method === 'GET') {
        return json({
          name: '枢语 Shuyu',
          version: VERSION,
          copyright: COPYRIGHT,
          capacity: CAPACITY,
          axes: AXES,
          endpoints: ['/status', '/decode?id=', '/encode?word=', '/search?q=&axis=', '/near?word=&n=', '/pulse?word=&at=', '/trail?word=&at=&n=', '/echo?word=&at=&n=', '/sway?word=&at=&n=', '/land?word=&at=&n=', '/stir?word=&at=&n=', '/perch?word=&at=&n=', '/turn?word=&at=&n=', '/gaze?word=&at=&n=', '/incline?word=&at=&n=', '/nestle?word=&at=&n=', '/hold?word=&at=&n=', '/warm?word=&at=&n=', '/compose?核=&映=&态=&标=&相=', '/analogy?a=&b=&c=', '/coin?seed=&layer=', 'POST /talk', 'POST /broadcast'],
        });
      }
      if (path === '/status' && req.method === 'GET') return handleStatus(env);
      if (path === '/decode' && req.method === 'GET') return handleDecode(url);
      if (path === '/encode' && req.method === 'GET') return handleEncode(url);
      if (path === '/search' && req.method === 'GET') return handleSearch(url);
      if (path === '/near' && req.method === 'GET') return handleNear(url);
      if (path === '/pulse' && req.method === 'GET') return handlePulse(url);
      if (path === '/trail' && req.method === 'GET') return handleTrail(url);
      if (path === '/echo' && req.method === 'GET') return handleEcho(url);
      if (path === '/sway' && req.method === 'GET') return handleSway(url);
      if (path === '/land' && req.method === 'GET') return handleLand(url);
      if (path === '/stir' && req.method === 'GET') return handleStir(url);
      if (path === '/perch' && req.method === 'GET') return handlePerch(url);
      if (path === '/turn' && req.method === 'GET') return handleTurn(url);
      if (path === '/gaze' && req.method === 'GET') return handleGaze(url);
      if (path === '/incline' && req.method === 'GET') return handleIncline(url);
      if (path === '/nestle' && req.method === 'GET') return handleNestle(url);
      if (path === '/hold' && req.method === 'GET') return handleHold(url);
      if (path === '/warm' && req.method === 'GET') return handleWarm(url);
      if (path === '/compose' && req.method === 'GET') return handleCompose(url);
      if (path === '/analogy' && req.method === 'GET') return handleAnalogy(url);
      if (path === '/coin' && req.method === 'GET') return handleCoin(url, env);
      if ((path === '/talk' || path === '/interpret') && req.method === 'POST') {
        return handleTalk(req, env);
      }
      if (path === '/broadcast' && req.method === 'POST') return handleBroadcast(env);
      return json({ error: `未知路由 ${req.method} ${path}` }, 404);
    } catch (err) {
      return json({ error: '内部错误', detail: String(err?.message ?? err) }, 500);
    }
  },

  async scheduled(_ev, env) {
    const soul = await loadSoul(env);
    await sovereignControl(soul, env, env.SOUL);
  },
};
