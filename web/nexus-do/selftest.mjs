// 神枢 · 纯逻辑自测（无需 Workers 运行时）
// 用法：node build.mjs && node selftest.mjs
import { ShenshuCore } from './nexus_do.mjs';
import { decode, encode, CAPACITY, coinWord } from './lexicon.js';
import { resolveCapability, describeCapabilities, capabilitySelfDescription, CAPABILITIES } from './capabilities.mjs';

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

// ── 记忆召回做深：时间衰减 + 重要度加权 ──
const NOW = 1000 * 86400000;
const soulRecent = { episodes: [
  { 他说: '部署项目到服务器', 我说了: '好', ts: NOW - 1 * 86400000 },
  { 他说: '部署项目到服务器', 我说了: '好', ts: NOW - 300 * 86400000 },
] };
ok('召回：相关度相同则新近优先', S.retrieveMemories(soulRecent, '服务器部署项目', 2, NOW)[0].ts === NOW - 1 * 86400000);
const soulImp = { episodes: [
  { 他说: '服务器随便看看', 我说了: '好', ts: NOW },
  { 他说: '服务器 重要 密钥 部署 记住', 我说了: '好', ts: NOW },
] };
ok('召回：新近相同则重要度优先', S.retrieveMemories(soulImp, '服务器', 2, NOW)[0].他说.includes('重要'));

// ── 省 Key = 分级路由：简单→light（免费CF）、复杂→heavy（Claude网关）──
ok('闲聊/短句 → light', S.pickTier('在吗', []) === 'light' && S.pickTier('今天天气不错', []) === 'light');
ok('技术/复杂 → heavy', S.pickTier('帮我分析这段代码为什么报错', []) === 'heavy');
ok('长文 → heavy', S.pickTier('一'.repeat(70), []) === 'heavy');
ok('深度/代码 cap → heavy', S.pickTier('随便说说', ['code']) === 'heavy' && S.pickTier('嗯', ['think']) === 'heavy');

// ── 联网检索触发判定（保守触发：显式检索意图 或 新鲜+事实）──
ok('显式检索意图 → 需联网', S.needsWeb('帮我查一下今天的油价') && S.needsWeb('搜索一下最新消息') && S.needsWeb('google 一下这个词'));
ok('新鲜+事实性问句 → 需联网', S.needsWeb('比特币现在多少钱') && S.needsWeb('今天天气怎么样'));
ok('普通闲聊/技术不误触发', !S.needsWeb('在吗') && !S.needsWeb('帮我写个排序算法') && !S.needsWeb('你是谁'));
ok('空/极短不触发', !S.needsWeb('') && !S.needsWeb('嗯'));

// ── 真 agent 执行环：工具调用解析 + 标记清理（确定性，可测）──
ok('解析 web_search 工具调用', (() => { const c = S.parseToolCalls('先查一下 ⟨工具:web_search｜比特币最新价格⟩'); return c.length === 1 && c[0].tool === 'web_search' && c[0].arg === '比特币最新价格'; })());
ok('解析 open 网页工具调用', (() => { const c = S.parseToolCalls('⟨工具:open｜https://example.com/a⟩'); return c.length === 1 && c[0].tool === 'open' && c[0].arg === 'https://example.com/a'; })());
ok('多工具调用全部解析（兼容半角|）', S.parseToolCalls('⟨工具:web_search|甲⟩ 再 ⟨工具:open|https://x⟩').length === 2);
ok('无工具标记 → 空（视为最终答案）', S.parseToolCalls('这是最终答案，没有工具').length === 0);
ok('未知工具名不误抓', S.parseToolCalls('⟨工具:rm_rf｜/⟩').length === 0);
ok('清理残留工具标记', S.stripToolMarks('答案在此 ⟨工具:web_search｜x⟩ 结束') === '答案在此 结束');

// ── 能力契约鉴权硬门（LAUNCH_CHECKLIST 血泪教训：匿名不得越权）──
ok('未知能力被拒', resolveCapability('nope', true).ok === false && resolveCapability('nope', false).reason === 'unknown_capability');
ok('owner_only 能力：匿名拒绝', resolveCapability('soul', false).ok === false && resolveCapability('soul', false).reason === 'owner_only');
ok('owner_only 能力：主人放行', resolveCapability('soul', true).ok === true);
ok('全部能力均为 owner_only（无匿名可调）', CAPABILITIES.every(c => c.owner_only === true));
ok('匿名 describe 不泄露任何能力', describeCapabilities(false).length === 0);
ok('能力自述无人格词', !/贴身|撒娇|权哥|老公|想你/.test(capabilitySelfDescription(true)));

// ── 内在「越用越懂你」回路：蒸馏用户模型 + 喂回 ──
let um = { topics: {}, style: {}, entities: {}, count: 0 };
um = S.distillUserModel(um, '帮我看下这段 python 代码为什么报错', '');
um = S.distillUserModel(um, '再帮我调试下部署脚本的 bug', '');
um = S.distillUserModel(um, '嗯', '');
ok('用户模型累计话题（代码）', um.topics.代码 >= 2);
ok('用户模型识别风格（短句→简短）', um.style.简短 >= 1);
um = S.distillUserModel(um, '把 blackgod 项目的服务器配置发我', '');
ok('用户模型抓在意实体', Object.keys(um.entities).some(k => /blackgod/i.test(k)));
const umSum = S.summarizeUserModel(um);
ok('用户模型能喂回上下文（生成认知摘要）', /越用越懂/.test(umSum) && /代码/.test(umSum));
ok('空模型不产生噪音', S.summarizeUserModel({ count: 0 }) === '');

// ── 内在失败复盘：识别不满 + 喂回避免重蹈 ──
ok('识别不满（开头/含否定）', S.detectDissatisfaction('不对，重来') && S.detectDissatisfaction('这答非所问') && !S.detectDissatisfaction('好的谢谢'));
const failSum = S.summarizeFailures([{ 被否: '给你一堆没用的清单', 反应: '太啰嗦' }]);
ok('失败复盘喂回上下文', /避免重蹈/.test(failSum) && /换个方向/.test(failSum));
ok('无失败不产噪', S.summarizeFailures([]) === '');

// ── 自主心跳主动消息：真从内在状态生成 + 去人格 ──
ok('主动消息用未竟往事', /部署/.test(S.composeProactive({ episodes: [{ 他说: '帮我把生产部署搞定' }] })));
ok('主动消息用常聊话题', /代码/.test(S.composeProactive({ user_model: { topics: { 代码: 5 } } })));
ok('无状态时克制默认', S.composeProactive({}) === '主人，神枢在此待命，有需要随时说。');
ok('主动消息无人格词', !/想你|老公|不敢说|撒娇|宝贝|等他/.test(S.composeProactive({ episodes: [{ 他说: '部署' }] })));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
