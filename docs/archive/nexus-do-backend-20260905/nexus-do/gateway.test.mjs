// 网关模型自动识别 · 回归测试（起本地 mock 网关，真跑 probeModels + auto 闭环）
// 用法：node build.mjs && node gateway.test.mjs
import http from 'node:http';
import { ShenshuCore } from './nexus_do.mjs';

let pass = 0, fail = 0;
const ok = (n, c) => { if (c) { pass++; console.log('✓', n); } else { fail++; console.error('✗', n); } };

const mkInst = (cfg = {}) => {
  const store = new Map([['config', cfg]]);
  const inst = Object.create(ShenshuCore.prototype);
  inst.storage = { get: async k => store.get(k), put: async (k, v) => void store.set(k, v) };
  inst.env = {};
  return { inst, store };
};

// ── 端点推导（纯函数）──
{ const { inst } = mkInst();
  ok('推导 /v1 → /v1/models', inst.modelsEndpoint('https://x/v1') === 'https://x/v1/models');
  ok('推导 /v1/ 去尾斜杠', inst.modelsEndpoint('https://x/v1/') === 'https://x/v1/models');
  ok('推导 完整 chat/completions → /models', inst.modelsEndpoint('https://x/v1/chat/completions') === 'https://x/v1/models');
  ok('推导 /messages 端点 → /models', inst.modelsEndpoint('https://x/v1/messages') === 'https://x/v1/models');
}

// ── mock 网关：不同 path 回不同格式 ──
let modelsHits = 0, chatModelSeen = null, retryChatHits = 0;
const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  const auth = req.headers['authorization'] || '';
  let body = ''; req.on('data', c => body += c); req.on('end', () => {
    if (req.url === '/openai/models') { res.end(JSON.stringify({ object: 'list', data: [{ id: 'sihan-max' }, { id: 'gpt-4o' }, { id: 'sihan-max' }] })); return; }
    if (req.url === '/wrap/models') { res.end(JSON.stringify({ models: ['claude-opus', 'llama-3'] })); return; }
    if (req.url === '/arr/models') { res.end(JSON.stringify(['m-a', 'm-b'])); return; }
    if (req.url === '/empty/models') { res.end(JSON.stringify({ data: [] })); return; }
    if (req.url === '/needkey/models') { if (!/^Bearer\\s+\\S+/.test(auth)) { res.statusCode = 401; res.end(JSON.stringify({ error: 'unauthorized' })); return; } res.end(JSON.stringify({ data: [{ id: 'ok-model' }] })); return; }
    if (req.url === '/auth/models') { res.end(JSON.stringify({ data: [{ id: 'ok-model' }] })); return; }
    if (req.url === '/invalid/models') { res.setHeader('Content-Type', 'text/plain'); res.end('{bad json'); return; }
    if (req.url === '/v1/models') { modelsHits++; res.end(JSON.stringify({ data: [{ id: 'sihan-max' }, { id: 'gpt-4o' }] })); return; }
    if (req.url === '/v1/chat/completions') { chatModelSeen = JSON.parse(body || '{}').model; res.end(JSON.stringify({ choices: [{ message: { content: '在呢，权哥。' } }] })); return; }
    if (req.url === '/retry/v1/chat/completions') {
      retryChatHits++;
      if (retryChatHits === 1) { res.statusCode = 503; res.end(JSON.stringify({ error: { message: 'temporary down' } })); return; }
      res.end(JSON.stringify({ choices: [{ message: { content: '重试后成功。' } }] }));
      return;
    }
    if (req.url === '/status429/v1/chat/completions') { res.statusCode = 429; res.end(JSON.stringify({ error: { message: 'too many requests' } })); return; }
    if (req.url === '/slow/v1/chat/completions') { setTimeout(() => res.end(JSON.stringify({ choices: [{ message: { content: '慢回包。' } }] })), 120); return; }
    res.statusCode = 404; res.end(JSON.stringify({ error: 'not found' }));
  });
});
await new Promise(r => server.listen(0, r));
const port = server.address().port;
const U = p => `http://127.0.0.1:${port}${p}`;

// ── probeModels：三种响应格式 + 去重 + 错误处理 + 鉴权 ──
{ const { inst } = mkInst();
  const r = await inst.probeModels({ gateway_url: U('/openai') });
  ok('OpenAI data 格式识别', r.ok && r.count === 2 && r.models[0] === 'sihan-max' && r.models.includes('gpt-4o'));
  ok('重复模型已去重', r.models.filter(m => m === 'sihan-max').length === 1);
}
{ const { inst } = mkInst();
  const r = await inst.probeModels({ gateway_url: U('/wrap/chat/completions') });
  ok('models 包装格式识别 + 完整端点推导', r.ok && r.count === 2 && r.models.includes('claude-opus'));
}
{ const { inst } = mkInst();
  const r = await inst.probeModels({ gateway_url: U('/arr') });
  ok('纯数组格式识别', r.ok && r.models.join(',') === 'm-a,m-b');
}
{ const { inst } = mkInst();
  ok('空列表返回错误', (await inst.probeModels({ gateway_url: U('/empty') })).error !== undefined);
  ok('无网关地址返回错误', /先填网关地址/.test((await inst.probeModels({})).error || ''));
}
{ const { inst } = mkInst();
  const bad = await inst.probeModels({ gateway_url: U('/needkey') });
  ok('缺 key 返回 401 错误', !bad.ok && /401/.test(bad.error));
  const good = await inst.probeModels({ gateway_url: U('/auth'), gateway_key: 'sk-real' });
  ok('带正确 key 识别成功', good.ok && good.models[0] === 'ok-model');
}
{ const { inst } = mkInst();
  const bad = await inst.probeModels({ gateway_url: U('/invalid') });
  ok('无效 JSON 返回明确诊断', /无效 JSON/.test(bad.error || ''));
}
{ const { inst } = mkInst({ gateway_url: U('/auth'), gateway_key: 'sk-real' });
  const r = await inst.probeModels({ gateway_url: U('/auth'), gateway_key: '••••real' });
  ok('掩码 key 回退已存真 key', r.ok && r.models[0] === 'ok-model');
}
{ const { inst } = mkInst();
  const set1 = await inst.setConfig({ gateway_url: 'https://api.example.com/v1/chat/completions' });
  const cfg = await inst.getConfig(false);
  ok('setConfig 会规范化 OpenAI 兼容地址路径', set1.ok && cfg.gateway_url === 'https://api.example.com/v1');
  const badSet = await inst.setConfig({ gateway_url: 'https://api.example.com/v1?key=demo' });
  ok('setConfig 拒绝 URL query 里的隐式密钥', !badSet.ok && /不要带 \?query/.test(badSet.error || ''));
}

// ── auto 闭环：留空模型 → 自动识别 → 回复 → 缓存 → 命中缓存 ──
{ const store = new Map([['config', { gateway_url: U('/v1'), gateway_key: '', gateway_model: '' }]]);
  const inst = Object.create(ShenshuCore.prototype);
  inst.storage = { get: async k => store.get(k), put: async (k, v) => void store.set(k, v) };
  inst.env = {};
  const r1 = await inst.callBrain('你是神枢', '你好', { 心绪: 0.6 }, { tier: 'heavy' });
  ok('auto 闭环:留空模型也能成功回复', r1 && r1.reply === '在呢，权哥。');
  ok('auto 闭环:自动识别取第一个真实模型 sihan-max（不再硬传 auto）', chatModelSeen === 'sihan-max');
  ok('auto 闭环:识别结果已缓存 _auto_models[url]', (store.get('config')._auto_models || {})[U('/v1')] === 'sihan-max');
  const hitsBefore = modelsHits;
  const r2 = await inst.callBrain('你是神枢', '再说句', { 心绪: 0.6 }, { tier: 'heavy' });
  ok('auto 闭环:二次调用命中缓存不重复联网识别', r2 && r2.reply === '在呢，权哥。' && modelsHits === hitsBefore);
}
{ const { inst } = mkInst();
  const r = await inst.callGateway(U('/retry/v1'), '', 'sihan-max', 'sys', 'hi', 'openai');
  ok('callGateway 仅对暂时性 5xx 做有界重试', r.ok && r.reply.includes('重试后成功') && retryChatHits === 2);
}
{ const { inst } = mkInst();
  const r = await inst.callGateway(U('/status429/v1'), '', 'sihan-max', 'sys', 'hi', 'openai');
  ok('429 错误如实透传不静默回退', !r.ok && /HTTP 429/.test(r.err || ''));
}
{ const { inst } = mkInst();
  const ac = new AbortController();
  ac.abort();
  const r = await inst.callGateway(U('/slow/v1'), '', 'sihan-max', 'sys', 'hi', 'openai', { signal: ac.signal, timeoutMs: 1000 });
  ok('客户端取消会传递到网关调用', !r.ok && /取消/.test(r.err || ''));
}
{ const store = new Map([['config', { gateway_url: U('/slow/v1'), gateway_key: '', gateway_model: 'sihan-max' }]]);
  const inst = Object.create(ShenshuCore.prototype);
  inst.storage = { get: async k => store.get(k), put: async (k, v) => void store.set(k, v) };
  inst.env = {};
  const ac = new AbortController();
  ac.abort();
  const r = await inst.callBrain('你是神枢', '你好', { 心绪: 0.6 }, { tier: 'heavy', signal: ac.signal });
  ok('callBrain 支持上游取消透传', r && r.model === 'cancelled');
}

// ── 地址填错不静默消失：诚实报错要点名是哪条脑、错在哪 ──
{ const store = new Map([['config', { gateway_url: 'https://api.example.com/v1?key=leaked' }]]);
  const inst = Object.create(ShenshuCore.prototype);
  inst.storage = { get: async k => store.get(k), put: async (k, v) => void store.set(k, v) };
  inst.env = {};
  const r = await inst.callBrain('你是神枢', '你好', { 心绪: 0.6 }, { tier: 'heavy' });
  ok('网关地址不合法时诚实点名（不静默丢脑）', r.model === 'error' && /网关地址填错了/.test(r.reply) && /主网关/.test(r.reply));
}

server.close();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
