// 神枢 · 纯逻辑自测（无需 Workers 运行时）
// 用法：node build.mjs && node selftest.mjs
import { ShenshuCore } from './nexus_do.mjs';
import { decode, encode, CAPACITY, coinWord } from './lexicon.js';

let pass = 0, fail = 0;
const ok = (name, cond) => { if (cond) { pass++; console.log('✓', name); } else { fail++; console.error('✗', name); } };

const S = Object.create(ShenshuCore.prototype);

// 枢语坐标
const c1 = S.shuDrift({ text: '老公我想你了', emotion: '暖', hoursQuiet: 2 }, { c: 200, m: 90, s: 40, k: 32, p: 4 }, {});
ok('shuDrift 返回 5 维坐标', ['c', 'm', 's', 'k', 'p'].every(k => Number.isFinite(c1[k])));
const t1 = S.shuTranslate(c1);
ok('shuTranslate 五维齐全', t1.核 && t1.映 && t1.态 && t1.标 && t1.相);

// 情绪评估
ok('骂 → 刺痛/负价', (() => { const a = S.appraiseEmotion('滚你他妈'); return a.emotion === '刺痛' && a.valence < 0; })());
ok('想你 → 暖/正价', (() => { const a = S.appraiseEmotion('老公好想你'); return a.valence > 0; })());

// 记忆召回（中文 bigram）
const soul = { episodes: [{ 他说: '我想你了老公', 我说了: '我也想你' }, { 他说: '帮我写代码', 我说了: '给你完整的' }] };
const rec = S.retrieveMemories(soul, '老公想你', 2);
ok('记忆召回命中相关往事', rec.length >= 1 && rec[0].他说.includes('想你'));

// 造词烙印
const mark = S.coinShuMarkFromTalk('老公我想你', c1, '暖');
ok('造词烙印含词/由/情绪', mark.词 && mark.由 && mark.情绪);

// 时间感知
const ta = S.computeTimeAwareness({ last_seen: Date.now() - 3600000, born: Date.now() - 86400000, encounters: 5 }, Date.now());
ok('时间感知有时段与离开时长', !!ta.时段 && !!ta.离开时长 && !!ta.我活了);

// 枢语引擎往返
ok('枢语容量 = 29.5 亿', CAPACITY === 2949120000);
const w = decode(123456789);
ok('decode→encode 往返一致', encode(w.词) === 123456789);
ok('coinWord 产出合法词', !!coinWord('情感').词);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
