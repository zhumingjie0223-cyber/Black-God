// 神枢 · 伪命令桥自测（纯逻辑，无需 Workers 运行时）
// 用法：node build.mjs && node bridge.test.mjs
import { ShenshuCore } from './nexus_do.mjs';

let pass = 0, fail = 0;
const ok = (name, cond) => { if (cond) { pass++; console.log('✓', name); } else { fail++; console.error('✗', name); } };

function makeCore({ owner = 'OWNER-T0KEN' } = {}) {
  const S = Object.create(ShenshuCore.prototype);
  const store = new Map();
  S.env = owner ? { OWNER_TOKEN: owner } : {};
  S.storage = { get: async k => store.get(k), put: async (k, v) => { store.set(k, v); } };
  S.markCognitiveDirty = () => { S._dirtied = true; };
  const records = [];
  S.memoryExperience = {
    search: (q) => records.filter(r => JSON.stringify(r).includes(q)),
    remember: (kind, payload) => { const rec = { id: 'em-t-' + (records.length + 1), kind, at: Date.now(), payload }; records.push(rec); return rec; },
  };
  return { S, store, records };
}

// 1) 未配 OWNER_TOKEN → 桥令牌为空（路由侧即 fail-closed 拒绝）
{
  const { S } = makeCore({ owner: '' });
  ok('未配 OWNER_TOKEN → 桥令牌为空(桥关死)', (await S._bridgeToken()) === '');
}
// 2) 配了 OWNER_TOKEN → 64 位十六进制哈希，且不等于令牌本体、两次取值稳定
{
  const { S } = makeCore();
  const t1 = await S._bridgeToken(), t2 = await S._bridgeToken();
  ok('桥令牌=64位哈希且≠主人令牌本体', /^[0-9a-f]{64}$/.test(t1) && t1 !== 'OWNER-T0KEN' && t1 === t2);
}
// 3) 未知能力 → 拒绝并报白名单
{
  const { S } = makeCore();
  const r = await S.handleBridge('exec.run', { cmd: 'rm -rf /' });
  ok('未知能力(exec.run) → 拒绝', r.ok === false && /未知能力/.test(r.error));
}
// 4) memory.note → 写入 + 标脏；memory.search → 能搜回来
{
  const { S } = makeCore();
  const w = await S.handleBridge('memory.note', { text: '权哥喜欢玉绿色' });
  const s = await S.handleBridge('memory.search', { q: '玉绿' });
  ok('memory.note 写入且标脏', w.ok === true && !!w.id && S._dirtied === true);
  ok('memory.search 搜回刚写的记忆', s.ok === true && s.count === 1 && s.hits[0].payload.text.includes('玉绿'));
}
// 5) memory.search 缺关键词 → 报错不炸
{
  const { S } = makeCore();
  const r = await S.handleBridge('memory.search', {});
  ok('memory.search 缺 q → 报错', r.ok === false);
}
// 6) shuyu.query → 用存储词典检索（命中/未命中都成型）
{
  const { S, store } = makeCore();
  store.set('词典', { 词条: { a: { 词: '心澜', 义: '心里泛起的波澜', 罗: 'xinlan', count: 3, last_ts: 1 } }, 总数: 1 });
  const hit = await S.handleBridge('shuyu.query', { q: '心澜' });
  const miss = await S.handleBridge('shuyu.query', { q: '不存在的词xyz' });
  ok('shuyu.query 命中词条', hit.ok === true && hit.命中 === 1 && hit.词条[0].词 === '心澜');
  ok('shuyu.query 未命中也成型', miss.ok === true && miss.命中 === 0);
}
// 7) soul.status → 只暴露白名单字段
{
  const { S, store } = makeCore();
  store.set('soul', { version: 7, current_shu_coord: [1, 2, 3, 4, 5], miss_you: 0.4, secret_stuff: 'x' });
  const r = await S.handleBridge('soul.status', {});
  ok('soul.status 只出白名单字段', r.ok === true && r.version === 7 && r.miss_you === 0.4 && !('secret_stuff' in r));
}
// 8) 出门信封：cmd→command 双写 + /exec 附桥（PUBLIC_URL+OWNER_TOKEN 齐备时）
{
  const { S } = makeCore();
  S.env.PUBLIC_URL = 'https://nexus-do.example.workers.dev/';
  const b = await S._withBridgeEnvelope('/exec', { cmd: 'echo hi', timeout: 60 });
  ok('信封:cmd 双写为 command', b.command === 'echo hi' && b.cmd === 'echo hi');
  ok('信封:/exec 附桥且去尾斜杠', !!b.bridge && b.bridge.url === 'https://nexus-do.example.workers.dev/bridge' && /^[0-9a-f]{64}$/.test(b.bridge.token));
  const n = await S._withBridgeEnvelope('/browse', { url: 'https://x' });
  ok('信封:非 exec 路径不附桥', !n.bridge);
}
// 9) 未配 OWNER_TOKEN → /exec 信封不附桥（容器拿不到任何令牌）
{
  const { S } = makeCore({ owner: '' });
  S.env.PUBLIC_URL = 'https://nexus-do.example.workers.dev';
  const b = await S._withBridgeEnvelope('/exec', { cmd: 'echo hi' });
  ok('未配主人令牌 → 不附桥', !b.bridge);
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
