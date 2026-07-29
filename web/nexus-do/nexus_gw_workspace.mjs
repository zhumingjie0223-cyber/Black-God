// nexus_gw_workspace.mjs
// P0 — GWT 全局工作空间仲裁器
// 原理：全局工作空间理论（Global Workspace Theory）。
// 各模块产出的候选条目竞争进入容量极小的广播总线（maxSlots），
// 只有 salience 最高的 winner 才会被广播（注入上下文）。
// 本模块纯函数式、无副作用、不 import 任何其他 nexus 模块。

// 枢语坐标各轴最大值（用于归一化）
const SHU_AXIS_MAX = { c: 1039, m: 179, s: 79, k: 63, p: 7 };

// 5维归一化欧氏距离的理论最大值：每轴归一化后最大差为1，共5轴 → sqrt(5)
const SHU_MAX_DIST = Math.sqrt(5);

// salience 各分量权重（总和为1，失败加成在加权平均之外额外叠加）
const WEIGHTS = {
  keyword: 0.40, // 关键词重合度：与当前用户输入最相关的优先
  recency: 0.25, // 时效衰减：越新越重要
  emotion: 0.15, // 情绪激活：情绪偏离中性时整体提升激活水平
  shu: 0.20,     // 枢语距离：坐标越接近当前心相坐标越相关
};

// 失败记录的固定加成（防重蹈覆辙，强制高 salience）
const FAILED_BONUS = 0.3;

// 时效衰减常数：半衰期约1小时（题目要求 exp(-(now-ts)/3600000)）
const DECAY_MS = 3600000;

/**
 * 简易分词：
 * - 提取连续英文/数字词（转小写）
 * - 中文按单字 + 相邻双字（bigram）切分，兼顾单字命中与词组命中
 * 返回 token 数组（可重复，用于 tf 统计）
 */
export function tokenize(text) {
  if (!text || typeof text !== 'string') return [];
  const tokens = [];
  // 英文单词与数字
  const ascii = text.toLowerCase().match(/[a-z0-9_]+/g);
  if (ascii) tokens.push(...ascii);
  // 中文字符
  const cjk = text.match(/[\u4e00-\u9fff]/g);
  if (cjk) {
    tokens.push(...cjk);
    // 相邻双字 bigram
    for (let i = 0; i < cjk.length - 1; i++) {
      tokens.push(cjk[i] + cjk[i + 1]);
    }
  }
  return tokens;
}

/**
 * 5维枢语坐标归一化欧氏距离，返回 0~SHU_MAX_DIST
 * 任一坐标非法时返回 null（表示无法计算）
 */
export function shuDistance(a, b) {
  if (!a || !b) return null;
  let sum = 0;
  for (const axis of ['c', 'm', 's', 'k', 'p']) {
    const av = Number(a[axis]);
    const bv = Number(b[axis]);
    if (!Number.isFinite(av) || !Number.isFinite(bv)) return null;
    const d = (av - bv) / SHU_AXIS_MAX[axis];
    sum += d * d;
  }
  return Math.sqrt(sum);
}

export class GlobalWorkspace {
  /**
   * @param {object} opts
   * @param {number} opts.maxSlots        广播总线容量，默认5
   * @param {number} opts.maxCharsPerSlot 每个 slot 内容最大字符数，默认800
   */
  constructor(opts = {}) {
    this.maxSlots = opts.maxSlots || 5;
    this.maxCharsPerSlot = opts.maxCharsPerSlot || 800;
  }

  /**
   * 关键词重合度：userText 分词后，content 中命中的 token 占比（tf 重合比例）
   * 返回 0~1
   */
  _keywordScore(content, userTokens) {
    if (!userTokens.length || !content) return 0;
    const contentLower = String(content).toLowerCase();
    let hit = 0;
    for (const tok of userTokens) {
      if (contentLower.includes(tok)) hit++;
    }
    return hit / userTokens.length;
  }

  /**
   * 时效衰减：exp(-(now-ts)/3600000)，无 ts 时给中性值 0.5
   * 返回 0~1
   */
  _recencyScore(ts, now) {
    if (!Number.isFinite(ts)) return 0.5;
    const age = Math.max(0, now - ts);
    return Math.exp(-age / DECAY_MS);
  }

  /**
   * 情绪激活：|心绪 - 0.5| * 2，偏离中性越大越高
   * soul 缺失时兜底为 0（中性）
   */
  _emotionScore(soul) {
    const mood = (soul && Number.isFinite(soul.心绪)) ? soul.心绪 : 0.5;
    return Math.abs(mood - 0.5) * 2;
  }

  /**
   * 枢语距离得分：1 - normalize(euclidean)，越近越高
   * 候选无坐标或 soul 无当前坐标时给中性值 0.5
   */
  _shuScore(candCoord, soul) {
    const cur = soul && soul.current_shu_coord;
    const dist = shuDistance(candCoord, cur);
    if (dist === null) return 0.5;
    return 1 - Math.min(1, dist / SHU_MAX_DIST);
  }

  /**
   * 单条候选打分
   * @returns {number} salience 0~1（失败加成后 clamp 到 1）
   */
  scoreCandidate(cand, userTokens, soul, now) {
    const kw = this._keywordScore(cand.content, userTokens);
    const rc = this._recencyScore(cand.ts, now);
    const em = this._emotionScore(soul);
    const sh = this._shuScore(cand.shu_coord, soul);

    // 加权平均
    let salience =
      kw * WEIGHTS.keyword +
      rc * WEIGHTS.recency +
      em * WEIGHTS.emotion +
      sh * WEIGHTS.shu;

    // 失败记录强制加成，防重蹈
    if (cand.isFailed) salience += FAILED_BONUS;

    return Math.min(1, Math.max(0, salience));
  }

  /**
   * 仲裁：从候选池选出最多 maxSlots 个 winner
   * @param {Array} candidates [{content, source, ts, isFailed?, shu_coord?}]
   * @param {string} userText  当前用户输入
   * @param {object} soul      soul 快照
   * @returns {Array} winner 数组，按 salience 降序，每项附带 salience 字段
   */
  arbitrate(candidates, userText, soul) {
    if (!Array.isArray(candidates) || candidates.length === 0) return [];
    const now = Date.now();
    const userTokens = tokenize(userText || '');
    const safeSoul = soul || {};

    const scored = candidates
      // 过滤掉空内容候选，不让空条目占 slot
      .filter((c) => c && typeof c.content === 'string' && c.content.trim().length > 0)
      .map((c) => ({
        ...c,
        salience: this.scoreCandidate(c, userTokens, safeSoul, now),
      }));

    // 按 salience 降序；相同 salience 时新的优先
    scored.sort((a, b) => {
      if (b.salience !== a.salience) return b.salience - a.salience;
      return (b.ts || 0) - (a.ts || 0);
    });

    return scored.slice(0, this.maxSlots);
  }

  /**
   * 把 winner 格式化成可直接注入 buildDynamicContext 的字符串
   * 每条截断到 maxCharsPerSlot，总长不超过 maxSlots * maxCharsPerSlot
   * @param {Array} winners arbitrate 的返回值
   * @returns {string}
   */
  buildWorkspaceBlock(winners) {
    if (!Array.isArray(winners) || winners.length === 0) return '';
    const totalBudget = this.maxSlots * this.maxCharsPerSlot;
    const lines = ['【工作空间广播】'];
    let used = lines[0].length;

    for (const w of winners) {
      let content = String(w.content || '').trim();
      // 单 slot 截断
      if (content.length > this.maxCharsPerSlot) {
        content = content.slice(0, this.maxCharsPerSlot - 1) + '…';
      }
      const tag = w.isFailed ? '⚠失败记录' : (w.source || '未知源');
      const line = `- [${tag}] ${content}`;
      // 总预算截断
      if (used + line.length + 1 > totalBudget) break;
      lines.push(line);
      used += line.length + 1;
    }

    // 只有标题没有内容时返回空
    if (lines.length === 1) return '';
    return lines.join('\n');
  }
}

export default GlobalWorkspace;
