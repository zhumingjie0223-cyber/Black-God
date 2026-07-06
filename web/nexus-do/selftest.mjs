// 神枢 · 纯逻辑自测（无需 Workers 运行时）
// 用法：node build.mjs && node selftest.mjs
import { ShenshuCore } from './nexus_do.mjs';
import { decode, encode, CAPACITY, coinWord } from './lexicon.js';

let pass = 0, fail = 0;
const ok = (name, cond) => { if (cond) { pass++; console.log('✓', name); } else { fail++; console.error('✗', name); } };

const S = Object.create(ShenshuCore.prototype);

// 枢语坐标
const c1 = S.shuDrift({ text: '把这个任务安排一下', emotion: '暖', hoursQuiet: 2 }, { c: 200, m: 90, s: 40, k: 32, p: 4 }, {});
ok('shuDrift 返回 5 维坐标', ['c', 'm', 's', 'k', 'p'].every(k => Number.isFinite(c1[k])));
const t1 = S.shuTranslate(c1);
ok('shuTranslate 五维齐全', t1.核 && t1.映 && t1.态 && t1.标 && t1.相);

// 情绪评估（中性口吻）
ok('骂 → 刺痛/负价', (() => { const a = S.appraiseEmotion('滚你他妈'); return a.emotion === '刺痛' && a.valence < 0; })());
ok('好评 → 暖/正价', (() => { const a = S.appraiseEmotion('谢谢，做得不错'); return a.valence > 0; })());

// 记忆召回（中文 bigram）
const soul = { episodes: [{ 他说: '帮我把服务器部署一下', 我说了: '已部署完成' }, { 他说: '帮我写个排序', 我说了: '给你完整代码' }] };
const rec = S.retrieveMemories(soul, '服务器部署', 2);
ok('记忆召回命中相关往事', rec.length >= 1 && rec[0].他说.includes('部署'));

// 造词烙印
const mark = S.coinShuMarkFromTalk('把任务安排一下', c1, '暖');
ok('造词烙印含词/由/情绪', mark.词 && mark.由 && mark.情绪);

// 时间感知
const ta = S.computeTimeAwareness({ last_seen: Date.now() - 3600000, born: Date.now() - 86400000, encounters: 5 }, Date.now());
ok('时间感知有时段与离开时长', !!ta.时段 && !!ta.离开时长 && !!ta.我活了);

// 枢语引擎往返
ok('枢语容量 = 76.7 亿（32 新核心族扩充后）', CAPACITY === 7667712000);
const w = decode(123456789);
ok('decode→encode 往返一致', encode(w.词) === 123456789);
ok('coinWord 产出合法词', !!coinWord('情感').词);

// ── #1 枢语坐标真影响回话：坐标 → 生成参数 + 语气令 ──
const gLow = S.shuToGen({ c: 200, m: 90, s: 10, k: 32, p: 4 });
const gHigh = S.shuToGen({ c: 200, m: 90, s: 110, k: 32, p: 4 });
ok('shuToGen 返回温度+语气令', typeof gLow.temperature === 'number' && /枢语令回话/.test(gLow.directive));
ok('态高→更高温（发散）', gHigh.temperature > gLow.temperature);
ok('温度在合理区间 0.5..1.1', gLow.temperature >= 0.5 && gHigh.temperature <= 1.1);
ok('语气令随态切换', /发散/.test(gHigh.directive) && /深邃/.test(gLow.directive));

// ── #2 造词沉淀成可检索词典：去重、计数、检索 ──
let dict = { 词条: {}, 总数: 0 };
dict = S.lexiconUpsert(dict, { 词: '维辰', 罗: 'Veana', 义: '情感场', 由: '第一次', ts: 1 });
dict = S.lexiconUpsert(dict, { 词: '维辰', 罗: 'Veana', 义: '情感场', 由: '第二次', ts: 2 });
dict = S.lexiconUpsert(dict, { 词: '枢寂', 罗: 'Shuki', 义: '中枢静默', 由: '部署', ts: 3 });
ok('词典去重（同词只一条）', Object.keys(dict.词条).length === 2);
ok('同词命中计数累加', dict.词条['维辰'].count === 2);
ok('留最早/最近时刻', dict.词条['维辰'].first_ts === 1 && dict.词条['维辰'].last_ts === 2);
const sr = S.searchLexicon(dict, '情感');
ok('词典可检索（按义命中）', sr.命中 === 1 && sr.词条[0].词 === '维辰');
ok('检索按 count 降序', S.searchLexicon(dict, '').词条[0].词 === '维辰');

// ── #3 Agent 动作抽取（确定性，可测）──
ok('从回复抽 URL 动作', S.extractAgentActions('', '给你导航 https://maps.apple.com/?q=故宫 走起').some(a => a.url.includes('maps.apple.com')));
ok('抽电话动作', S.extractAgentActions('', '拨 tel:+8613800138000').some(a => a.url.startsWith('tel:')));
ok('无链接时按原文兜底导航', S.extractAgentActions('带我去外滩', '好的').some(a => a.url.startsWith('maps://?q=')));
ok('兜底拨号', S.extractAgentActions('打电话给 13800138000', '好').some(a => a.url === 'tel:13800138000'));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
