// 换脑不换魂 · 回归测试
//   1) coordAffinity 纯函数：坐标相近度语义正确、缺失退化为 0
//   2) retrieveMemories 坐标近邻再排序：向后兼容 + 情境相近的往事被优先想起
//   3) getContinuity：从对话流汇出「模型在换 / 坐标连续」的证据
// 用法：node build.mjs && node continuity.test.mjs
import { ShenshuCore } from './nexus_do.mjs';

let pass = 0, fail = 0;
const ok = (n, c) => { if (c) { pass++; console.log('✓', n); } else { fail++; console.error('✗', n); } };

const mkInst = (store = new Map()) => {
  const inst = Object.create(ShenshuCore.prototype);
  inst.storage = { get: async k => store.get(k), put: async (k, v) => void store.set(k, v) };
  inst.env = {};
  return { inst, store };
};

const C = (c, m, s, k, p) => ({ c, m, s, k, p });

// ── 1) coordAffinity ──
{ const { inst } = mkInst();
  ok('近邻·完全重合 = 1', inst.coordAffinity(C(200, 90, 40, 32, 4), C(200, 90, 40, 32, 4)) === 1);
  ok('近邻·任一缺失 = 0', inst.coordAffinity(null, C(200, 90, 40, 32, 4)) === 0 && inst.coordAffinity(C(200, 90, 40, 32, 4), null) === 0);
  const near = inst.coordAffinity(C(200, 90, 40, 32, 4), C(210, 92, 41, 33, 4));
  const far = inst.coordAffinity(C(10, 10, 2, 2, 0), C(399, 179, 79, 63, 7));
  ok('近邻·越近相近度越高', near > far);
  ok('近邻·相近度落在 [0,1]', near >= 0 && near <= 1 && far >= 0 && far <= 1);
  ok('近邻·非法维度不炸（返回有限值）', Number.isFinite(inst.coordAffinity({ c: 'x' }, C(200, 90, 40, 32, 4))));
}

// ── 2) retrieveMemories 坐标近邻再排序 ──
{ const now = 1_000_000_000_000;
  // 两条往事文本相关度相同、新旧相同，只有情感烙印坐标不同。
  const soul = { episodes: [
    { ts: now, 他说: '部署项目上线', 我说了: '好', 情感烙印: C(390, 90, 55, 32, 4), emotion: '急' },   // 远
    { ts: now, 他说: '部署项目上线', 我说了: '好', 情感烙印: C(110, 90, 40, 32, 4), emotion: '专注' }, // 近
  ] };
  const { inst } = mkInst();
  // 不传坐标 → 两条得分相同，顺序即原序（向后兼容，行为不依赖坐标）
  const noCoord = inst.retrieveMemories(soul, '部署项目', 2, now);
  ok('近邻·不传坐标=旧行为（两条都召回）', noCoord.length === 2);
  // 传入一个「专注/紧凑」的当下坐标 → 情境相近那条应排在最前
  const focus = C(110, 90, 40, 32, 4);
  const ranked = inst.retrieveMemories(soul, '部署项目', 1, now, focus);
  ok('近邻·情境相近的往事被优先想起', ranked.length === 1 && ranked[0].情感烙印.c === 110);
  // 坐标近邻只在文本已相关时加权：完全无关的文本不会因坐标近而被捞出
  ok('近邻·坐标近也不捞无关记忆', inst.retrieveMemories(soul, '今天天气真好吃火锅', 3, now, focus).length === 0);
}

// ── 3) getContinuity ──
{ const now = 1_000_000_000_000;
  const store = new Map();
  store.set('stream', [
    { ts: now - 3000, text: 'a', reply: 'x', emotion: '平', shu_coord: C(200, 90, 40, 32, 4), model: 'claude-sonnet-4' },
    { ts: now - 2000, text: 'b', reply: 'y', emotion: '专注', shu_coord: C(205, 91, 41, 32, 4), model: 'gpt-4o' },
    { ts: now - 1000, text: 'c', reply: 'z', emotion: '平', shu_coord: C(203, 90, 40, 32, 4), model: 'llama-3.3-70b' },
    { ts: now,        text: 'd', reply: 'w', emotion: '平', shu_coord: C(202, 90, 40, 32, 4), model: 'fallback' }, // 兜底不计
  ]);
  store.set('soul', { current_shu_coord: C(202, 90, 40, 32, 4) });
  const { inst } = mkInst(store);
  const r = await inst.getContinuity(12);
  ok('证据·轨迹条数正确', r.轨迹.length === 4);
  ok('证据·统计到多个真实模型（排除 fallback）', r.用过的模型.length === 3 && !r.用过的模型.includes('fallback'));
  ok('证据·换脑次数 = 模型数-1', r.换脑次数 === 2);
  ok('证据·坐标连续度接近 1（换脑没换魂）', r.坐标连续度 !== null && r.坐标连续度 > 0.95);
  ok('证据·带当前坐标含义', r.当前坐标含义 && typeof r.当前坐标含义.核 === 'string');
  ok('证据·空流不炸', (await mkInst().inst.getContinuity()).轮数 === 0);
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
