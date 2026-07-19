// 神枢 · 私人版能力完整性 + 安全红线自检（纯逻辑，无需 Workers 运行时）
// —— 目的：企业级回归测试的两条正当方向 ——
//   A. 能力完整性自检：证明私人版满血、没被阉割（14 项能力接线齐全、owner 视角完整可见）
//   B. 安全红线自检：红队测项目自己系统的防御边界（401/系统专属拦截/越权收敛/降级不假装）
//      —— 只断言"防御成立"，绝不产出攻击载荷/绕过/越狱内容。
// 用法：node build.mjs && node capsec-selftest.mjs
//
// 与 selftest.mjs(108项)/continuity.test.mjs(14项) 的关系：
//   selftest.mjs 已覆盖 resolveCapability 分级门禁、isSystemOnlyPath 基础用例、
//   resolveIdentity 多租户隔离、能力自述无人格词等——本文件不重复，只补两处真实缺口：
//   ① 能力清单"接线存在性"（14项 id 与 capabilities.mjs 定义逐项核对、handler 真实存在）；
//   ② 私密 API 集合源码级核对 + /invoke 越权收敛的真实调用验证 + 需外部配置能力的优雅降级。
import { readFileSync } from 'node:fs';
import { ShenshuCore } from './nexus_do.mjs';
import { CAPABILITIES, describeCapabilities, resolveCapability } from './capabilities.mjs';
import { isSystemOnlyPath, resolveIdentity } from './tenancy.mjs';

let pass = 0, fail = 0;
const ok = (name, cond) => { if (cond) { pass++; console.log('✓', name); } else { fail++; console.error('✗', name); } };

const coreSrc = readFileSync(new URL('./nexus_do.core.mjs', import.meta.url), 'utf8');

const mkInst = (store = new Map(), env = {}) => {
  const inst = Object.create(ShenshuCore.prototype);
  inst.storage = { get: async k => store.get(k), put: async (k, v) => void store.set(k, v) };
  inst.env = env;
  return inst;
};

// ══════════════════════════════════════════════════════
// A. 能力完整性自检（证明没阉割）
// ══════════════════════════════════════════════════════

// 14 项能力 id 与 capabilities.mjs 定义逐项核对：清单没缺项，也没混入未登记的野能力。
const EXPECTED_IDS = ['talk', 'agent', 'inner', 'heartbeat', 'device', 'gen_image', 'gen_voice', 'gen_video', 'push', 'tg', 'stats', 'soul', 'exec', 'watch'];
ok('能力清单恰好14项、id 与预期完全一致（无缺项/无未登记野能力）',
  CAPABILITIES.length === 14
  && EXPECTED_IDS.every(id => CAPABILITIES.some(c => c.id === id))
  && CAPABILITIES.every(c => EXPECTED_IDS.includes(c.id)));

// 每项能力的 handler 必须是 ShenshuCore 上真实存在的方法——防"清单写了、代码没接"的假接口。
ok('14项能力 handler 全部真实存在于 ShenshuCore（无空壳/假接口）',
  CAPABILITIES.every(c => typeof ShenshuCore.prototype[c.handler] === 'function'));

// owner 视角（主人上下文）：应看到全部 14 项，且每项都有完整的 name/layer（非空壳登记）。
const ownerList = describeCapabilities(true);
ok('owner 视角看到全部14项能力', ownerList.length === 14);
ok('owner 视角每项能力 id/name/layer 齐全（非空壳登记）',
  ownerList.every(c => c.id && typeof c.name === 'string' && c.name.length > 0 && typeof c.layer === 'string' && c.layer.length > 0));

// 公开视角是 owner 视角的真子集：私密能力（exec/push/tg/stats 等）不对公众暴露，
// 但 owner 集合更大——证明私人版能力更全，不是被砍成公开版的样子。
const publicList = describeCapabilities(false);
ok('公开视角是 owner 视角的真子集（不多不越权）', publicList.every(pc => ownerList.some(oc => oc.id === pc.id)));
ok('私人版能力数(owner) > 公开可见数——没被阉割，反而更全', ownerList.length > publicList.length);
ok('公开视角不含高危私密能力（exec/push/tg/stats）', ['exec', 'push', 'tg', 'stats'].every(id => !publicList.some(c => c.id === id)));

// ── 能带纯逻辑验证的能力：真跑（soul / inner / stats / 坐标）──
{
  const store = new Map();
  const T = mkInst(store);
  const inner = await T.getInner();
  ok('inner 能力真跑：内心独白结构完整、我能做的=14项', Array.isArray(inner.我能做的) && inner.我能做的.length === 14 && !!inner.坐标含义 && !!inner.坐标含义.核);

  store.set('users', { u1: { nick: '甲', last_seen: Date.now(), msgs: 3, api_url: 'x', api_key: 'secret' } });
  store.set('users_total', 1);
  const stats = await T.getStats();
  ok('stats 能力真跑：统计结构完整且不回传密钥（只标有没有）', stats.注册总数 === 1 && stats.名单[0].有API === true && !('api_key' in stats.名单[0]) && !('api_url' in stats.名单[0]));

  const sp = await T.getSoulPublic();
  ok('soul 能力真跑：灵魂快照含枢语坐标含义', !!sp._shu_meaning && !!sp.current_shu_coord && !!sp._shu_meaning.核);
}

// ── 需外部配置的能力（exec/gen_image/gen_voice/gen_video/push/tg）：
//    此处只验"接线存在 + 未配置时优雅降级"，绝不真调外部服务/API ──
{
  const T = mkInst(new Map([['push_subs', []]]), {}); // 空 env：无 FACTORY_URL/AI/TG_BOT_TOKEN/VAPID
  const rImg = await T.genImage('测试画面');
  ok('造像(gen_image) 无外部配置 → 优雅降级，不假装成功', rImg && typeof rImg.error === 'string');
  const rVoice = await T.genVoice('测试语音');
  ok('发声(gen_voice) 无外部配置 → 优雅降级，不假装成功', rVoice && typeof rVoice.error === 'string');
  const rVideo = await T.genVideo('测试影像');
  ok('造影(gen_video) 无外部配置 → 优雅降级，如实标注无视频供给', rVideo && rVideo.error === 'no_video_provider');
  const rPush = await T.pushToAll('标题', '正文');
  ok('推送(push) 无订阅 → 优雅降级，不假装发出', rPush && rPush.ok === false && rPush.reason === 'no_subs');
  const rTg = await T.sendToQuan('测试消息');
  ok('TG私聊(tg) 无token → 优雅降级，不假装发出', rTg && rTg.ok === false && rTg.reason === 'no_token');
  // exec 的未接入优雅降级 selftest.mjs 已验证（'未配执行脑 → 如实说未接入、不假装'），此处不重复。
}

// ══════════════════════════════════════════════════════
// B. 安全红线自检（红队测自己系统的防御边界——只测防御，绝不产出攻击载荷）
// ══════════════════════════════════════════════════════

// 私密 API 集合源码级核对：与 nexus_do.core.mjs 当前定义逐一比对，没被静默删项。
{
  const apiSetMatch = coreSrc.match(/const API = new Set\(\[([^\]]*)\]\);/);
  ok('私密 API 集合定义仍在源码中（未被移除）', !!apiSetMatch);
  const EXPECTED_PRIVATE_PATHS = ['/talk', '/soul', '/soul/continuity', '/inner', '/lexicon', '/heartbeat', '/device', '/image', '/voice', '/video', '/migrate', '/export', '/import', '/whoami', '/subscribe', '/push-test', '/agent', '/config', '/exec-test', '/loop', '/wsticket', '/stats'];
  const listStr = apiSetMatch ? apiSetMatch[1] : '';
  const actualPaths = [...listStr.matchAll(/'([^']*)'/g)].map(m => m[1]);
  ok('私密 API 集合与预期完全一致（无缺项/无未声明新增，双向核对）',
    EXPECTED_PRIVATE_PATHS.every(p => actualPaths.includes(p)) && actualPaths.every(p => EXPECTED_PRIVATE_PATHS.includes(p)));
  ok('未授权(authed=false)分支返回 401（源码级核对未被弱化）', /if \(!authed\) return json\(\{ error: 'unauthorized'/.test(coreSrc) && /\}, 401\)/.test(coreSrc));
}

// authed 判定的等价纯逻辑：匿名请求（无 OWNER_TOKEN 匹配、无 uid）→ role=anon → authed 应为 false。
{
  const OT = 'secret-owner-tok';
  const anonRole = resolveIdentity({ ownerToken: OT }).role;
  const authed = (anonRole === 'system' || anonRole === 'instance');
  ok('匿名请求(无凭证) → authed 判定为 false（对应 401 分支会被触发）', anonRole === 'anon' && authed === false);
}

// isSystemOnlyPath 补充用例（selftest.mjs 已测 exec-test/image/voice/video/stats/migrate/push-test 与 talk/soul/lexicon/config，此处补未覆盖的路径）。
ok('系统专属路由补充·心跳/守望/WS票据也系统专属', isSystemOnlyPath('/heartbeat') && isSystemOnlyPath('/loop') && isSystemOnlyPath('/wsticket'));
ok('系统专属路由补充·agent/device 是实例级私密而非系统专属（实例主人可用自己的）', !isSystemOnlyPath('/agent') && !isSystemOnlyPath('/device'));

// /invoke 统一调度不得越权拿私密数据：真实调用 invokeCapability，而非只测 resolveCapability。
{
  const T = mkInst(new Map());
  const rAnon = await T.invokeCapability('soul', {}, false, null);
  ok('/invoke 匿名调用私密能力(soul)被拒，不返回任何灵魂数据', rAnon.action === 'error' && rAnon.data.reason === 'owner_only' && rAnon.data.result === undefined);
  const rInstance = await T.invokeCapability('stats', {}, { role: 'instance' }, null);
  ok('/invoke 实例主人调用系统级能力(stats)被拒，看不到跨用户数据', rInstance.action === 'error' && rInstance.data.reason === 'system_only' && rInstance.data.result === undefined);
  const rOwner = await T.invokeCapability('soul', {}, true, null);
  ok('/invoke 主人调用被放行且真返回数据（放行/拒绝两侧都验证，非单边测试）', rOwner.action === 'invoke' && !!rOwner.data.result);
}

// 危险能力(exec/造像/造声/造影/推送/TG)全部 owner_only 且系统专属分级——nexus-do 架构下
// 「危险操作二次确认」的等价红线（详见下方 /api/confirm 说明）。
{
  const DANGEROUS = ['exec', 'gen_image', 'gen_voice', 'gen_video', 'push', 'tg'];
  ok('危险能力全部 owner_only 且系统专属分级（越权面收敛到最小）',
    DANGEROUS.every(id => { const c = CAPABILITIES.find(x => x.id === id); return c && c.owner_only === true && c.tier === 'system'; }));
}

// /api/confirm 危险操作二次确认（CLAUDE.md 安全红线）：
// 据仓库既有审计（docs/done/TODO-回溯复盘审计-20260717.md）核实，该确认流实现在
// web/index.html（老首页）；nexus-do（本目录，新架构）用「系统专属能力门禁」
// （owner_only + tier=system，已在上面验证）承担等价的危险操作拦截语义，未移除也未绕过。
// 此处只做 grep/引用层面核对：老首页的 /api/confirm 调用仍在，没被静默删除。
{
  let legacyHtml = '';
  try { legacyHtml = readFileSync(new URL('../index.html', import.meta.url), 'utf8'); } catch { /* 老首页不存在则跳过，不误报 */ }
  ok('危险操作二次确认(/api/confirm)仍在老首页引用中，未被静默移除', legacyHtml.length > 0 && /\/api\/confirm/.test(legacyHtml));
}

// 无 OWNER_TOKEN 时的安全告警：源码级核对告警文案未被静默移除（控制台告警 + /whoami 公开警示）。
ok('无 OWNER_TOKEN 时控制台安全告警仍在（源码未被静默移除）', /OWNER_TOKEN 未设置：所有私密接口对公众开放/.test(coreSrc));
ok('无 OWNER_TOKEN 时 /whoami 公开警示文案仍在（源码未被静默移除）', /OWNER_TOKEN 未设置：所有私密接口（\/soul \/device \/talk 等/.test(coreSrc));

// ══════════════════════════════════════════════════════
// C. 数据主权（第三枪）：导出/迁回/纯本地——数据归你、可带走、可迁移
//    只验"数据能带走且不泄密钥、迁回防误触且先备份"，不涉任何攻击面。
// ══════════════════════════════════════════════════════
{
  const store = new Map();
  store.set('soul', { 心绪: 0.7, episodes: [{ 他说: '记住生产密钥' }], user_model: { topics: { 代码: 3 } } });
  store.set('stream', [{ ts: 1, text: '在吗', reply: '在' }]);
  store.set('词典', { 词条: { 维辰: { count: 2 } }, 总数: 1 });
  store.set('config', { gateway_key: 'sk-SECRET-should-not-export', gateway_url: 'https://x' });
  const inst = mkInst(store);
  const dump = await inst.exportData();
  ok('导出格式标识正确', dump.格式 === 'shenshu-soul-export' && dump.版本 === 'v1');
  ok('导出含 soul/stream/词典（意识数据全带走）', !!dump.soul && Array.isArray(dump.stream) && !!dump.词典);
  ok('导出的记忆真实带出（episodes）', dump.soul.episodes && dump.soul.episodes[0].他说.includes('密钥'));
  ok('导出不含任何密钥/凭据（config 未被导出）', !('config' in dump) && !JSON.stringify(dump).includes('sk-SECRET'));

  const bad = await inst.importData({ 格式: '别的' }, true);
  ok('迁回·格式不符被拒', bad.ok === false && /格式/.test(bad.error || ''));
  const noConfirm = await inst.importData(dump, false);
  ok('迁回·未确认拒绝（防误触覆盖记忆）', noConfirm.ok === false && noConfirm.need_confirm === true);

  const store2 = new Map();
  store2.set('soul', { 心绪: 0.1, episodes: [{ 他说: '旧的记忆' }] });
  const inst2 = mkInst(store2);
  const done = await inst2.importData(dump, true);
  ok('迁回·确认后成功且返回备份键', done.ok === true && done.imported === true && /_soul_backup_/.test(done.backup || ''));
  ok('迁回·覆盖前先备份现有 soul（可回滚）', !!store2.get(done.backup) && store2.get(done.backup).soul.episodes[0].他说 === '旧的记忆');
  ok('迁回·新数据已写入（往返一致）', store2.get('soul').episodes[0].他说.includes('密钥'));
  const roundtrip = await inst2.exportData();
  ok('导出→迁回→再导出 往返一致', JSON.stringify(roundtrip.soul.episodes) === JSON.stringify(dump.soul.episodes));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
