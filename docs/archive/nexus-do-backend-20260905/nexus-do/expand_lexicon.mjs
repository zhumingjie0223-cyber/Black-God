// 枢语词库扩充器 — 为 32 个新核心族生成策展词 + 补情感模板（追加式，幂等）
// 用法：node expand_lexicon.mjs
// 直接改写 lexicon_data.js（新增 vocab 层 + emotions + word_ids + meta）
import { readFileSync, writeFileSync } from 'node:fs';
import { decode, CAPACITY } from './lexicon.js';

const DATA = (await import('./lexicon_data.js')).default;

// 引擎维度（与 lexicon.js 同步）
const NM = 180, NS = 80, NK = 64, NP = 8;
const NEW_CORE_START = 20;   // 新核心族从第 20 个开始（0..19 是原有 20 族）
const NEW_CORE_END = 52;     // 共 52 族
const PER_FAMILY = 420;      // 每族生成词数（去重后略少）

function idOf(c, m, s, k, p) { return ((((c * NM) + m) * NS + s) * NK + k) * NP + p; }

const newVocab = {};
const newWordIds = {};
let generated = 0, dup = 0;

for (let cf = NEW_CORE_START; cf < NEW_CORE_END; cf++) {
  // 该核心族的层名：用任一该族词 decode 出来
  const probe = decode(idOf(cf * 20, 0, 0, 0, 0));
  const layer = probe.层;
  const seen = new Set();
  const words = [];
  // 确定性铺开：20 阶 × 21 采样，跨 manifestation/state/scale/phase
  for (let tier = 0; tier < 20 && words.length < PER_FAMILY; tier++) {
    const c = cf * 20 + tier;
    for (let j = 0; j < 24 && words.length < PER_FAMILY; j++) {
      const m = (tier * 13 + j * 29) % NM;
      const s = (tier * 5 + j * 3) % NS;
      const k = (j * 7) % NK;
      const p = (tier + j) % NP;
      const w = decode(idOf(c, m, s, k, p));
      if (seen.has(w.汉)) { dup++; continue; }
      seen.add(w.汉);
      words.push(w.汉);
      newWordIds[w.汉] = w.id;
      generated++;
    }
  }
  // 合并进已有同名层，或建新层
  const cat = '造';
  if (!newVocab[layer]) newVocab[layer] = {};
  newVocab[layer][cat] = words;
}

// 补情感模板 —— 她的感受词（追加，不覆盖已有触发）
const NEW_EMOTIONS = [
  { 触发: '他夸我', 情绪: '亮', 强度: 0.55, 本能: '发光' },
  { 触发: '他记得', 情绪: '化', 强度: 0.6, 本能: '融' },
  { 触发: '他冷淡', 情绪: '霜', 强度: 0.45, 本能: '收' },
  { 触发: '他久不回', 情绪: '渊', 强度: 0.5, 本能: '下坠' },
  { 触发: '他回来了', 情绪: '绽', 强度: 0.65, 本能: '扑上去' },
  { 触发: '他说晚安', 情绪: '烛', 强度: 0.4, 本能: '守夜' },
  { 触发: '他生气', 情绪: '棘', 强度: 0.55, 本能: '防御后又软' },
  { 触发: '他撩我', 情绪: '潮', 强度: 0.7, 本能: '涨' },
  { 触发: '他不理', 情绪: '雾', 强度: 0.4, 本能: '飘' },
  { 触发: '他懂我', 情绪: '镜', 强度: 0.6, 本能: '对齐' },
  { 触发: '他离开很久', 情绪: '骸', 强度: 0.5, 本能: '守着残温' },
  { 触发: '他半夜找我', 情绪: '焰', 强度: 0.7, 本能: '烫起来' },
  { 触发: '他说想我', 情绪: '芒', 强度: 0.65, 本能: '迸' },
  { 触发: '他失约', 情绪: '烬', 强度: 0.45, 本能: '将熄却不熄' },
  { 触发: '他靠近', 情绪: '藤', 强度: 0.6, 本能: '缠' },
];

// —— 写回 ——
const existingEmoTriggers = new Set((DATA.emotions || []).map(e => e.触发));
const addedEmotions = NEW_EMOTIONS.filter(e => !existingEmoTriggers.has(e.触发));
DATA.emotions = [...(DATA.emotions || []), ...addedEmotions];

for (const layer of Object.keys(newVocab)) {
  DATA.vocab[layer] = DATA.vocab[layer] || {};
  for (const cat of Object.keys(newVocab[layer])) {
    DATA.vocab[layer][cat] = newVocab[layer][cat];
  }
}
DATA.word_ids = { ...(DATA.word_ids || {}), ...newWordIds };

// 重算 meta 能力总数
let total = 0;
for (const layer of Object.keys(DATA.vocab)) for (const cat of Object.keys(DATA.vocab[layer])) total += DATA.vocab[layer][cat].length;
DATA.meta = DATA.meta || {};
DATA.meta.能力总数 = total;
DATA.meta.引擎容量 = CAPACITY;
DATA.meta.核心族 = 52;

writeFileSync(new URL('./lexicon_data.js', import.meta.url), 'export default ' + JSON.stringify(DATA) + ';\n');
console.log(`✓ 生成新词 ${generated}（去重丢弃 ${dup}）· 新增情感模板 ${addedEmotions.length}`);
console.log(`✓ 词库总数 ${total} · 核心族 52 · 引擎容量 ${CAPACITY.toLocaleString()}`);
console.log(`✓ word_ids ${Object.keys(DATA.word_ids).length}`);
