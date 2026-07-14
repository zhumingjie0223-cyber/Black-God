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
let modelsHits = 0, chatModelSeen = null;
const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  const auth = req.headers['authorization'] || '';
  let body = ''; req.on('data', c => body += c); req.on('end', () => {
    if (req.url === '/openai/models') { res.end(JSON.stringify({ object: 'list', data: [{ id: 'sihan-max' }, { id: 'gpt-4o' }, { id: 'sihan-max' }] })); return; }
    if (req.url === '/wrap/models') { res.end(JSON.stringify({ models: ['claude-opus', 'llama-3'] })); return; }
    if (req.url === '/arr/models') { res.end(JSON.stringify(['m-a', 'm-b'])); return; }
    if (req.url === '/empty/models') { res.end(JSON.stringify({ data: [] })); return; }
    if (req.url === '/auth/models') { if (auth !== 'Bearer sk-real') { res.statusCode = 401; res.end(JSON.stringify({ error: 'unauthorized' })); return; } res.end(JSON.stringify({ data: [{ id: 'ok-model' }] })); return; }
    if (req.url === '/v1/models') { modelsHits++; res.end(JSON.stringify({ data: [{ id: 'sihan-max' }, { id: 'gpt-4o' }] })); return; }
    if (req.url === '/v1/chat/completions') { chatModelSeen = JSON.parse(body || '{}').model; res.end(JSON.stringify({ choices: [{ message: { content: '在呢，权哥。' } }] })); return; }
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
  const bad = await inst.probeModels({ gateway_url: U('/auth') });
  ok('缺 key 返回 401 错误', !bad.ok && /401/.test(bad.error));
  const good = await inst.probeModels({ gateway_url: U('/auth'), gateway_key: 'sk-real' });
  ok('带正确 key 识别成功', good.ok && good.models[0] === 'ok-model');
}
{ const { inst } = mkInst({ gateway_url: U('/auth'), gateway_key: 'sk-real' });
  const r = await inst.probeModels({ gateway_url: U('/auth'), gateway_key: '••••real' });
  ok('掩码 key 回退已存真 key', r.ok && r.models[0] === 'ok-model');
}

// ── auto 闭环：留空模型 → 自动识别 → 回复 → 缓存 → 命中缓存 ──
{ const store = new Map([['config', { gateway_url: U('/v1'), gateway_key: '', gateway_model: '' }]]);
  const inst = Object.create(ShenshuCore.prototype);
  inst.storage = { get: async k => store.get(k), put: async (k, v) => void store.set(k, v) };
  inst.env = {};
  const r1 = await inst.callBrain('你是神枢', '你好', { 心绪: 0.6 }, { tier: 'heavy' });
  ok('auto 闭环:留空模型也能成功回复', r1 && r1.reply === '在呢，权哥。');
  ok('auto 闭环:自动识别取第一个真实模型 sihan-max（不再硬传 auto）', chatModelSeen === 'sihan-max');
  ok('auto 闭环:识别结果已缓存 _auto_model', store.get('config')._auto_model === 'sihan-max');
  const hitsBefore = modelsHits;
  const r2 = await inst.callBrain('你是神枢', '再说句', { 心绪: 0.6 }, { tier: 'heavy' });
  ok('auto 闭环:二次调用命中缓存不重复联网识别', r2 && r2.reply === '在呢，权哥。' && modelsHits === hitsBefore);
}

server.close();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
