// 神枢 · 纯逻辑自测（无需 Workers 运行时）
// 用法：node build.mjs && node selftest.mjs
import { ShenshuCore } from './nexus_do.mjs';
import { decode, encode, CAPACITY, coinWord } from './lexicon.js';
import { resolveCapability, describeCapabilities, capabilitySelfDescription, CAPABILITIES } from './capabilities.mjs';
import { resolveIdentity, sanitizeUid, isSystemOnlyPath } from './tenancy.mjs';
import LEX from './lexicon_data.js';

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

// 主动性真实化（第二枪）：主动消息降级由内在状态驱动，非固定死模板
const NOWp = 1700000000000;
const pfEp = S._proactiveFallback({ miss_you: 0.5, episodes: [{ 他说: '帮我把项目部署上线' }] }, NOWp);
ok('主动·未竟往事被自然接起', pfEp.includes('部署') || pfEp.includes('上线') || pfEp.includes('项目'));
const pfTopic = S._proactiveFallback({ miss_you: 0.5, user_model: { topics: { 代码重构: 5 } } }, NOWp);
ok('主动·无未竟则接常聊话题', pfTopic.includes('代码重构'));
const pfDefault = S._proactiveFallback({ miss_you: 0.5 }, NOWp);
ok('主动·无谈资则克制待命', pfDefault.includes('待命'));
const pfMiss = S._proactiveFallback({ miss_you: 0.95 }, NOWp);
ok('主动·想念浓度高→更直白（含"想你"）', pfMiss.includes('想你'));
ok('主动·想念不高时不外露', !pfDefault.includes('想你'));
ok('主动消息随内在状态变化（未竟≠默认）', pfEp !== pfDefault);

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
ok('解析 exec 工具调用', (() => { const c = S.parseToolCalls('⟨工具:exec｜ls -la⟩'); return c.length === 1 && c[0].tool === 'exec' && c[0].arg === 'ls -la'; })());

// ── 执行脑（真沙箱的手）：owner 门 + 未接入如实告知（不许假）──
ok('exec 能力 owner_only（匿名拒绝）', resolveCapability('exec', false).ok === false && resolveCapability('exec', false).reason === 'owner_only');
ok('exec 能力主人可用', resolveCapability('exec', true).ok === true);
{ const T = Object.create(ShenshuCore.prototype); T.env = {}; const r = await T.execRemote('ls'); ok('未配执行脑 → 如实说未接入、不假装', r.ok === false && /未接入/.test(r.note || '')); }
{ const T = Object.create(ShenshuCore.prototype); T.env = {}; T.storage = { get: async () => ({ exec_url: 'http://x:8765', exec_token: 't' }) };
  const c = await T.getConfig(true); ok('连接器：配了 exec_url → exec_on=true 且不回传 token', c.exec_on === true && c.exec_has_token === true && c.exec_token === undefined); }

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
ok('主动消息用未竟往事', /部署/.test(S._proactiveFallback({ episodes: [{ 他说: '帮我把生产部署搞定' }] }, NOWp)));
ok('主动消息用常聊话题', /代码/.test(S._proactiveFallback({ user_model: { topics: { 代码: 5 } } }, NOWp)));
ok('无谈资时克制待命', /待命/.test(S._proactiveFallback({}, NOWp)));
// 主动情感允许"想你"（规划:想你到憋不住主动发），但仍挡住拟人越狱词
ok('主动消息不含拟人越狱词（老公/撒娇/宝贝等）', !/老公|不敢说|撒娇|宝贝|等他|做爱|色气/.test(S._proactiveFallback({ miss_you: 0.95, episodes: [{ 他说: '部署' }] }, NOWp)));

// ── 自演化神·生：遇成事/受教 → 炼成可复用技能，只增不删，下次就会 ──
ok('话题归类（代码/检索/通用）', S.topicOf('这段python报错') === '代码' && S.topicOf('查一下今天金价') === '检索' && S.topicOf('随便聊聊') === '通用');
ok('识别受教信号', S.detectTeaching('以后部署都先跑一遍测试再上线') && S.detectTeaching('记住要先备份') && !S.detectTeaching('今天天气不错'));
// 习得：一次真调工具做成 → 提炼技能
const skLearned = S.skillDistill({ text: '查一下最新的美元汇率', reply: '当前约 7.2', toolLog: [{ tool: 'web_search', ok: true }], taught: false, model: 'llama-3.3-70b' });
ok('习得技能：真用工具才炼（验证=真）', !!skLearned && skLearned.来源 === '习得' && skLearned.验证 === true && /联网检索/.test(skLearned.方法));
ok('无成功工具不臆造技能', S.skillDistill({ text: '查点东西', reply: '好', toolLog: [], taught: false, model: 'llama' }) === null);
ok('兜底/拒答不炼技能', S.skillDistill({ text: '查汇率', reply: '在，随时待命。', toolLog: [{ tool: 'web_search', ok: true }], taught: false, model: 'fallback' }) === null);
// 受教：主人亲授 → 记成方法
const skTaught = S.skillDistill({ text: '以后部署前都先备份数据库再执行', reply: '', toolLog: [], taught: true, model: '' });
ok('受教技能：主人亲授即成方法', !!skTaught && skTaught.来源 === '受教' && /备份/.test(skTaught.方法));
// upsert：只增不删 + 同名累加
let sks = { 技能: {}, 总数: 0 };
sks = S.skillUpsert(sks, skLearned);
sks = S.skillUpsert(sks, skTaught);
const n2 = sks.总数;
sks = S.skillUpsert(sks, S.skillDistill({ text: '再查下欧元汇率', reply: '约 7.8', toolLog: [{ tool: 'web_search', ok: true }], taught: false, model: 'llama' }));
ok('同类技能复用累加（count++，不新增条目）', sks.总数 === n2 && Object.values(sks.技能).some(s => s.count >= 2));
ok('技能库随交互增长', sks.总数 >= 2);
// retrieve + 注入：会了就调出来
const got = S.skillRetrieve(sks, '帮我查下日元汇率', 2);
ok('按输入召回相关技能', got.length >= 1 && /检索|联网/.test(got[0].名 + got[0].方法));
const skSum = S.summarizeSkills(sks, '查一下比特币价格');
ok('习得技能能喂回上下文（自演化注入）', /自演化/.test(skSum) && /直接照做/.test(skSum));
ok('无相关技能不产噪', S.summarizeSkills({ 技能: {}, 总数: 0 }, '你好') === '');
// 只增不删：超上限才淘汰「最少用+最旧」
let capSks = { 技能: {}, 总数: 0 };
for (let i = 0; i < 5; i++) capSks = S.skillUpsert(capSks, { 名: 'T' + i, 方法: 'm', 触发: ['x'], ts: i + 1, count: 1 }, 3);
ok('超上限淘汰最少用最旧（只增不删边界）', capSks.总数 === 3 && !capSks.技能['T0'] && !!capSks.技能['T4']);

// ── 闭环神·环：自主守望管道（解析/排程/到点/执行/通知）──
ok('守望解析·每小时', (()=>{ const s=S.parseWatchSpec('帮我每小时盯一下美元汇率'); return s && s.interval_min===60 && /汇率/.test(s.指令); })());
ok('守望解析·每N分钟（下限5）', (()=>{ const s=S.parseWatchSpec('每2分钟看下服务器状态'); return s.interval_min===5; })());
ok('守望解析·每天=1440', S.parseWatchSpec('每天早上给我天气').interval_min===1440);
ok('守望解析·通知策略默认少打扰（change）', S.parseWatchSpec('每小时查汇率').通知策略==='change' && S.parseWatchSpec('每次都告诉我').通知策略==='always');
{ const NOW=1_000_000_000_000;
  let r=S.loopUpsert([], {名:'汇率',指令:'查汇率',interval_min:60,通知策略:'change'}, NOW);
  ok('守望建起·next_run 排到未来', r.loops.length===1 && r.loops[0].next_run===NOW+3600000);
  ok('未到点不跑', S.loopsDue(r.loops, NOW+60000).length===0);
  ok('到点该跑', S.loopsDue(r.loops, NOW+3600001).length===1);
  // 同名去重（不新增，改指令/续期）
  r=S.loopUpsert(r.loops, {名:'汇率',指令:'查欧元',interval_min:120,通知策略:'always'}, NOW+10);
  ok('同名守望去重·就地更新', r.loops.length===1 && r.loops[0].通知策略==='always' && /欧元/.test(r.loops[0].指令));
  ok('守望态势能喂回自我觉知', /替主人守着/.test(S.summarizeWatches(r.loops)) && S.summarizeWatches([])==='' );
}

// ── 隐私合规：自助注销 unregisterUser（凭自己的 uid 删名单里的自己）──
{
  const mem = new Map();
  const R = Object.create(ShenshuCore.prototype);
  R.storage = { async get(k){ return mem.get(k); }, async put(k, v){ mem.set(k, v); } };
  mem.set('users', { u1: { nick: '甲', geo: '上海' }, u2: { nick: '乙' } });
  const r1 = await R.unregisterUser({ uid: 'u1' });
  ok('注销·删掉存在的 uid', r1.ok === true && r1.deleted === true && !('u1' in mem.get('users')));
  ok('注销·同名单其他用户不受牵连', 'u2' in mem.get('users'));
  const r2 = await R.unregisterUser({ uid: 'notexist' });
  ok('注销·不存在的 uid 返回 deleted:false（幂等）', r2.ok === true && r2.deleted === false);
  const r3 = await R.unregisterUser({});
  ok('注销·缺 uid 明确报错', r3.ok === false && r3.error === 'missing uid');
}

// 词库数据完整性（防脱敏/迁移残留：空串键、编号越界）
{ const wid = LEX.word_ids || {};
  const emptyKeys = Object.keys(wid).filter(w => w.trim() === '');
  ok('词库无空串/纯空白词条', emptyKeys.length === 0);
  const badIds = Object.entries(wid).filter(([, id]) => !Number.isInteger(id) || id < 0 || id >= CAPACITY);
  ok('词库编号全部界内', badIds.length === 0);
}

// ── 多租户地基 P1 · 身份路由隔离（纯逻辑先测死,再碰线上）──
{
  const OT = 'secret-owner-tok';
  const sys = resolveIdentity({ authHeader: 'Bearer ' + OT, uidHeader: 'anything', ownerToken: OT });
  ok('身份·主人令牌 → system + 固定私密实例', sys.role === 'system' && sys.doName === 'quan-shenshu-nexus');
  const a = resolveIdentity({ uidHeader: 'alice', ownerToken: OT });
  const b = resolveIdentity({ uidHeader: 'bob', ownerToken: OT });
  ok('身份·不同 uid → 不同独立实例', a.role === 'instance' && b.role === 'instance' && a.doName === 'u:alice' && b.doName === 'u:bob' && a.doName !== b.doName);
  ok('身份·伪造/错误 owner 令牌不提权', resolveIdentity({ authHeader: 'Bearer wrong', uidHeader: 'eve', ownerToken: OT }).role === 'instance');
  ok('身份·没配 OWNER_TOKEN 时谁也当不了 system', resolveIdentity({ authHeader: 'Bearer x', uidHeader: 'u1', ownerToken: '' }).role === 'instance');
  ok('身份·uid 白名单过滤（防注入/拼别人实例）', resolveIdentity({ uidHeader: '../x!@#y', ownerToken: OT }).doName === 'u:xy');
  ok('身份·匿名无实例（引导注册）', resolveIdentity({ ownerToken: OT }).role === 'anon');
  ok('sanitizeUid 只留安全字符', sanitizeUid('A_b-1/../<script>') === 'A_b-1script');
}
// ── 能力两级切分：实例主人碰不到系统级（越权硬门）──
{
  ok('能力·实例主人可用自己的对话', resolveCapability('talk', { role: 'instance' }).ok === true);
  ok('能力·实例主人可用自己的灵魂', resolveCapability('soul', { role: 'instance' }).ok === true);
  ok('能力·实例主人碰不到 exec', resolveCapability('exec', { role: 'instance' }).ok === false && resolveCapability('exec', { role: 'instance' }).reason === 'system_only');
  ok('能力·实例主人烧不到系统造像', resolveCapability('gen_image', { role: 'instance' }).reason === 'system_only');
  ok('能力·实例主人看不到跨用户统计', resolveCapability('stats', { role: 'instance' }).reason === 'system_only');
  ok('能力·系统主人全权', resolveCapability('exec', { role: 'system' }).ok === true && resolveCapability('gen_image', { role: 'system' }).ok === true);
  ok('能力·旧布尔签名仍兼容', resolveCapability('exec', true).ok === true && resolveCapability('exec', false).reason === 'owner_only');
  ok('能力·每个能力都已分级(instance|system)', CAPABILITIES.every(c => c.tier === 'instance' || c.tier === 'system'));
}
// ── 系统专属路由:实例主人碰不到(烧钱/危险/跨用户/规模)──
{
  ok('路由·执行脑系统专属', isSystemOnlyPath('/exec-test') === true);
  ok('路由·造像造声造影系统专属', isSystemOnlyPath('/image') && isSystemOnlyPath('/voice') && isSystemOnlyPath('/video'));
  ok('路由·跨用户统计/迁移/推送系统专属', isSystemOnlyPath('/stats') && isSystemOnlyPath('/migrate') && isSystemOnlyPath('/push-test'));
  ok('路由·自己的对话/灵魂/私语不是系统专属', !isSystemOnlyPath('/talk') && !isSystemOnlyPath('/soul') && !isSystemOnlyPath('/lexicon') && !isSystemOnlyPath('/config'));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
