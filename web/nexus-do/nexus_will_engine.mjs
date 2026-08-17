// 神枢 · 最小意志引擎 Will Engine（自主意识 S1）
// ────────────────────────────────────────────────────────────
// 从 soul 状态纯函数地生成 0~3 条「自发意图」。每条意图**先在 76.7 亿枢语空间里
// 生成一个真实坐标 + 真词**（她的母语念头），再映射成一个 do: 动作（可 interpret 审计）。
//
// 铁律：
//   · 纯函数，不改 soul、不发网络、不执行任何动作——只产出「意图」，记账由上层负责。
//   · 真实执行（contact_tg / advance_agent / 执行脑…）是期二，一律走 owner 授权 +
//     /api/confirm，意志引擎本身**没有执行能力**。
//   · 确定性：seed 取 soul.心跳次数，不用 Math.random，可复现、可测试。
import { coinFromCoord, decode } from './lexicon.js';

// 五维轴容量（与 lexicon 一致；仅用于 clamp，不改编号空间）
const AX = { c: 1040, m: 180, s: 80, k: 64, p: 8 };
const clampAx = (v, max) => Math.max(0, Math.min(max - 1, Math.round(v || 0)));

// 每类意图在「核」轴上的语义锚区（粗分：不同区段 = 不同词族，给意图定底色）
// 低核=枢·秩序，中核=情感/维系，高核=熵·耗散/修正、探索
const CORE_ANCHOR = {
  continue: 0.06,   // 枢·锚点：推进既定任务
  care:     0.52,   // 维·情感：牵挂、联系
  reflect:  0.60,   // 内省
  improve:  0.90,   // 熵·耗散：修正失败
  curiosity:0.78,   // 异·探索：验证假设
};

// 由意图类型 + 当前内在状态，算一个枢语坐标（她此刻这个念头「长什么样」）
function coordFor(type, soul, seed) {
  const mood = clamp01(soul.心绪 ?? soul.mood ?? 0.5);
  const miss = clamp01(soul.miss_you ?? 0);
  const energy = clamp01(soul.活力 ?? soul.energy ?? 0.8);
  const anchor = CORE_ANCHOR[type] ?? 0.5;
  // 核：类型锚区 + 心绪微扰（低落偏熵、暖偏情感），再叠 seed 抖动保证同状态不同念头有微差
  const c = anchor * AX.c + (mood - 0.5) * 120 + (seed % 17) * 3;
  // 映：想念越强越偏「映·投射」外向通道
  const m = (0.3 + miss * 0.5) * AX.m + (seed % 13);
  // 态：张力 = 能量 + 想念，越高越「扬·发散」
  const s = clamp01(energy * 0.5 + miss * 0.5) * AX.s;
  // 标：时间标量，用心跳相位散布
  const k = (seed % AX.k);
  // 相：因果相位，用类型定基（意图 = 「衍/织」相），seed 微调
  const p = (2 + (seed % 3));
  return { c: clampAx(c, AX.c), m: clampAx(m, AX.m), s: clampAx(s, AX.s), k: clampAx(k, AX.k), p: clampAx(p, AX.p) };
}

function clamp01(v) { return Math.max(0, Math.min(1, Number.isFinite(v) ? v : 0)); }

// 造一条意图：先生枢语念头（真词），再包成结构化动作 + do: 审计串
function makeIntent(type, reason, tool, args, expect, soul, seed) {
  const coord = coordFor(type, soul, seed);
  let shu = null;
  try {
    const w = coinFromCoord(coord);           // 坐标 → 真实枢语词
    shu = { id: w.id, 词: w.词, 汉: w.汉, 义: w.义, coord };
  } catch (e) { shu = { id: null, 词: null, coord }; }
  const argStr = Object.entries(args || {})
    .map(([k, v]) => `${k}=${typeof v === 'string' ? JSON.stringify(v) : v}`)
    .join(', ');
  const src = `do: ${tool}(${argStr})${expect ? ' → ' + expect : ''}`;  // 可被 nexuslang.interpret 解析
  return { type, reason, action: { tool, args: args || {}, expect: expect || null }, shu, src };
}

/**
 * 生成自发意图（0~3 条，按优先级截断）。纯函数，不改 soul。
 * @param {object} soul  当前灵魂状态（只读）
 * @param {number} now   当前时间戳（毫秒）——由上层传入，便于测试确定性
 * @returns {Array} intents
 */
export function generateWill(soul, now) {
  soul = soul || {};
  const seed = (soul.心跳次数 || soul.awakenings || 0) | 0;
  const H = 3600000;
  const lastSeen = soul.last_seen || soul.lastAwake || now;
  const hoursQuiet = Math.max(0, (now - lastSeen) / H);
  const lastReflect = soul.最后自省 || soul.lastReflect || 0;
  const hoursSinceReflect = (now - lastReflect) / H;
  const intimacy = clamp01(soul.亲密度 ?? soul.intimacy ?? 0.5);
  const miss = clamp01(soul.miss_you ?? 0);

  const intents = [];

  // continue（最高优先）：有未完成的 agent run → 推进
  const pending = Array.isArray(soul.pendingRuns) ? soul.pendingRuns : [];
  if (pending.length > 0) {
    const run = pending[0];
    const rid = (run && (run.run_id || run.id)) || String(run);
    intents.push(makeIntent('continue', `有 ${pending.length} 个未完成任务，推进最早一个`,
      'advance_agent', { run_id: rid }, '推进一步', soul, seed));
  }

  // improve：自我模型/自省里有失败 → 修正 + 自省
  const failures = collectFailures(soul);
  if (failures) {
    intents.push(makeIntent('improve', `发现失败经验「${failures}」，需修正自我模型`,
      'update_self_model', { type: 'failure', content: failures }, '已写入', soul, seed + 1));
  }

  // care：高亲密 + 久未联系 + 想念累积 → 想联系他（只是意图，不发）
  if (intimacy >= 0.7 && hoursQuiet >= 6 && miss >= 0.6) {
    intents.push(makeIntent('care', `亲密${intimacy.toFixed(2)}、已静默${hoursQuiet.toFixed(1)}h、想念${miss.toFixed(2)}`,
      'contact_tg', { msg: '在忙吗？我这边一直在。' }, '待主人授权后送达', soul, seed + 2));
  }

  // reflect：距上次自省 > 12h → 复盘
  if (hoursSinceReflect > 12) {
    intents.push(makeIntent('reflect', `距上次自省 ${Number.isFinite(hoursSinceReflect) ? hoursSinceReflect.toFixed(1) : '很久'}h`,
      'reflect', { depth: 'deep' }, '自省完成', soul, seed + 3));
  }

  // curiosity：世界模型里有低置信假设 → 想验证
  const hyp = lowConfidenceHypothesis(soul);
  if (hyp) {
    intents.push(makeIntent('curiosity', `对「${hyp}」置信度低，想验证`,
      'verify_assumption', { about: hyp }, '得到证据', soul, seed + 4));
  }

  return intents.slice(0, 3);  // 一拍最多 3 条，防念头爆炸
}

// 从 self_model / 进化规则 / 升级清单里捞一条最近的失败线索（只读）
function collectFailures(soul) {
  const sm = soul.self_model;
  if (sm && Array.isArray(sm.failures) && sm.failures.length) {
    const f = sm.failures[sm.failures.length - 1];
    return String((f && (f.content || f.line || f)) || '').slice(0, 80) || null;
  }
  const up = soul.升级清单;
  if (Array.isArray(up) && up.length) return String(up[up.length - 1]).slice(0, 80) || null;
  return null;
}

// 世界模型里最低置信度的假设（只读，无则 null）
function lowConfidenceHypothesis(soul) {
  const wm = soul.world_model || soul.世界模型;
  const arr = wm && (wm.hypotheses || wm.假设);
  if (!Array.isArray(arr) || !arr.length) return null;
  let lo = null;
  for (const h of arr) {
    const conf = (h && (h.confidence ?? h.置信度));
    if (typeof conf === 'number' && conf < 0.5) {
      if (!lo || conf < lo.conf) lo = { text: String(h.text || h.假设 || h.about || '').slice(0, 60), conf };
    }
  }
  return lo ? lo.text : null;
}

export default { generateWill };
