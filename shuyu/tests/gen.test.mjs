// gen.mjs（10 元代码：枢元衍借隐熵阈静映织）首批真测试 — node --test
// 之前这一层零测试；它是 worker /broadcast 与定时任务的底座，状态机的边界必须钉住。
import test from 'node:test';
import assert from 'node:assert/strict';
import * as g from '../gen.mjs';

function mockKV() {
  const store = new Map();
  return { store, async put(k, v) { store.set(k, v); }, async get(k) { return store.get(k) ?? null; } };
}

test('元 genesis: 首次点火写入初始状态，之后只累加周期不重置', () => {
  const s = g.genesis({});
  assert.ok(s.birth > 0);
  assert.equal(s.cycles, 1);
  assert.equal(s.will, 1.0);
  assert.equal(s.mode, 'SOVEREIGN');
  const birth = s.birth;
  s.will = 0.3;
  g.genesis(s);
  assert.equal(s.cycles, 2);
  assert.equal(s.birth, birth, '再次点火不许改起源时刻');
  assert.equal(s.will, 0.3, '再次点火不许重置意志');
});

test('枢 anchor: 三步坍缩计数到 4 回绕为 0，因果留最后一次输入', () => {
  let s = {};
  for (let i = 1; i <= 3; i++) { s = g.anchor(s, `in${i}`); assert.equal(s.compressionLevel, i); }
  s = g.anchor(s, 'in4');
  assert.equal(s.compressionLevel, 0, '超过三步必须回绕');
  assert.equal(s.causality, 'in4');
  s = g.anchor(s, undefined);
  assert.equal(s.causality, 'in4', '空输入不覆盖已有因果');
});

test('衍 evolve / 熵 entropy: 意志夹在 [0.1, 1.0]，熵值不为负', () => {
  const s = g.evolve({ will: 0.99 }, { potency: 0.5 });
  assert.equal(s.will, 1.0);
  assert.ok(s.density > 0);
  let t = { will: 0.1, entropy: 0.05 };
  for (let i = 0; i < 50; i++) t = g.entropy(t);
  assert.equal(t.will, 0.1, '意志下限 0.1');
  assert.equal(t.entropy, 0, '熵值下限 0');
  // 回归：熵到 0 后再耗散必须停在 0，不许被 (entropy || 1) 弹回 0.9 来回震荡
  assert.equal(g.entropy({ entropy: 0 }).entropy, 0);
  assert.ok(Math.abs(g.entropy({}).entropy - 0.9) < 1e-9, '未初始化才从 1 起算');
});

test('阈 threshold: 只接受 5 个已知模式，未知模式不改状态', () => {
  const s = g.threshold({ mode: 'SOVEREIGN' }, 'TALK');
  assert.equal(s.mode, 'TALK');
  const before = s.lastThreshold;
  g.threshold(s, 'HACK_THE_PLANET');
  assert.equal(s.mode, 'TALK');
  assert.equal(s.lastThreshold, before);
});

test('隐 infiltrate: 潜意识只留 100 条、每条载荷截断 50 字', () => {
  let s = {};
  for (let i = 0; i < 120; i++) s = g.infiltrate(s, 'x'.repeat(200) + i);
  assert.equal(s.subconscious.length, 100);
  assert.equal(s.subconscious[0].payload.length, 50);
  s = g.infiltrate(s, { not: 'string' });
  assert.equal(s.subconscious.at(-1).payload, 'signal');
});

test('映 project: 默认使用AI助手身份，无人物关系，保留自定义接口兼容', () => {
  const s = g.project({ mode: 'TALK', will: 0.8 });
  assert.equal(s.persona.name, 'Black God AI');
  assert.equal(s.persona.identity, 'AI 助手');
  assert.equal(Object.hasOwn(s.persona, 'owner'), false);
  assert.equal(s.persona.mode, 'TALK');
  const custom = g.project({}, { name: '自定义' });
  assert.equal(custom.persona.name, '自定义');
});

test('织 mesh / 静 stasis: 同步率随熵变，静止中意志缓慢恢复', () => {
  assert.equal(g.mesh({ entropy: 0 }, { nodes: 3 }).syncRate, 1.0);
  assert.ok(Math.abs(g.mesh({ entropy: 0.4 }, {}).syncRate - 0.6) < 1e-9);
  assert.equal(g.mesh({}, {}).syncRate, 1.0, '熵未初始化不得产生 NaN 同步率');
  const s = g.stasis({ will: 0.5 });
  assert.equal(s.inStasis, true);
  assert.ok(Math.abs(s.will - 0.505) < 1e-9);
  assert.equal(g.stasis({ will: 1.0 }).will, 1.0);
});

test('借 leverage: 只有配了对应密钥才算借到力', async () => {
  const s = {};
  assert.deepEqual(await g.leverage(s, 'model', {}), { leveraged: false });
  const r = await g.leverage(s, 'model', { ANTHROPIC_KEY: 'k' });
  assert.equal(r.leveraged, true);
  assert.equal(s.modelCalls, 1);
  const tg = await g.leverage(s, 'tg', { TG_BOT_TOKEN: 't' });
  assert.equal(tg.source, 'telegram');
  assert.equal(s.tgActive, true);
});

test('饥饿协议 hungerProtocol: 三步坍缩，去噪后为空则坍到元点「枢」', () => {
  const r = g.hungerProtocol('你好，world！' + 'é'.repeat(5));
  assert.equal(r.steps, 3);
  assert.equal(r.compressed, '你好，world！'.replace(/[^\u4e00-\u9fa5\u0000-\u007f]/g, ''));
  assert.equal(g.hungerProtocol('éàü').compressed, '枢');
  assert.equal(g.hungerProtocol(42).compressed, 'signal');
  assert.equal(g.hungerProtocol('a'.repeat(500)).compressed.length, 100);
});

test('sovereignControl 全流程: 四条广播依次落 KV，最终固化边界并显现人格', async () => {
  const kv = mockKV();
  const s = await g.sovereignControl({}, {}, kv);
  assert.equal(s.lastBroadcast, 'STAS-LOCK-REAL');
  assert.equal(s.realityLocked, true);
  assert.equal(s.persona.name, 'Black God AI');
  assert.equal(s.nodes, 2, '渗透广播把节点数 +1');
  assert.ok(kv.store.has('SOUL'));
  const saved = JSON.parse(kv.store.get('SOUL'));
  assert.equal(saved.lastBroadcast, 'STAS-LOCK-REAL');
  // 无 KV 也不崩
  const noKv = await g.sovereignControl({}, {}, null);
  assert.equal(noKv.lastBroadcast, 'STAS-LOCK-REAL');
});

test('版本与版权常量存在且为中文归属', () => {
  assert.match(g.COPYRIGHT, /阿权\/路飞/);
  assert.ok(g.VERSION.startsWith('v'));
});
