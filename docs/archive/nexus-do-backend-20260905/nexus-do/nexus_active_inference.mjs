// =============================================================================
// nexus_active_inference.mjs — 主动推理执行环（P1）
// =============================================================================
// 原理：主动推理（Active Inference）。
//   执行前先生成对命令输出的"预期"，执行后计算预测误差（delta）。
//   误差低 → 世界模型没问题，继续 / 修命令即可；
//   误差高 → 不是命令写错了，是"我对这个环境的假设错了"，
//            先更新世界模型（soul.world_model），再基于新假设生成新命令。
//
// 依赖：无。callBrainFn 由 ShenshuCore 注入，本模块不 import 任何东西。
// 铁律：instanceMode 下 before() 直接返回 {expected:''}，不调 callBrain。
// =============================================================================

// ---- 内部常量：delta 各分量权重与策略阈值 --------------------------------
const W_FAIL = 0.3;        // 命令失败（!ok）的意外贡献
const W_STDERR = 0.1;      // stderr 非空的意外贡献
const W_MISMATCH = 0.6;    // 预期与实际的关键词错配贡献（最大值）
const THRESH_UPDATE = 0.75; // delta ≥ 此值且失败 → 世界模型有问题
const MAX_EXPECTED_LEN = 200;   // 预期文本上限
const MAX_LOG_ENTRIES = 50;     // inference_log 上限
const MAX_ASSUMPTIONS = 30;     // world_model.assumptions 上限
const MAX_ACTUAL_SAMPLE = 2000; // 参与分词的实际输出采样长度

// ---- 内部工具：分词（英文词 + 单个 CJK 字符）------------------------------
function tokenize(text) {
  if (!text || typeof text !== 'string') return [];
  const tokens = text.toLowerCase().match(/[a-z0-9_]+|[\u4e00-\u9fff]/g);
  return tokens || [];
}

// ---- 内部工具：预期 token 在实际输出中的覆盖率（0~1）----------------------
function coverage(expectedText, actualText) {
  const expTokens = tokenize(expectedText);
  if (expTokens.length === 0) return null; // 无预期，无法比较
  const actualSet = new Set(tokenize(actualText));
  let hit = 0;
  for (const t of expTokens) {
    if (actualSet.has(t)) hit++;
  }
  return hit / expTokens.length;
}

// ---- 内部工具：从大脑回复中尽力抠出一个 JSON 对象 --------------------------
function extractJson(text) {
  if (!text || typeof text !== 'string') return null;
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) return null;
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
}

export class ActiveInferenceEngine {

  // callBrainFn: (system, msg, soul, opts) => Promise<{reply}>
  // 由 ShenshuCore 注入，形如 (s,m,soul,o) => this.callBrain(s,m,soul,o)
  constructor(callBrainFn) {
    this.callBrainFn = typeof callBrainFn === 'function' ? callBrainFn : null;
  }

  // ==========================================================================
  // before — 执行前预测
  // 返回 {expected: string}，预期输出的关键特征，≤200字
  // instanceMode 下直接返回 {expected:''}，不调 callBrain（铁律）
  // ==========================================================================
  async before(cmd, soul, opts = {}) {
    // 实例模式：跳过预测，省一次大脑调用
    if (opts.instanceMode) return { expected: '' };
    if (!this.callBrainFn) return { expected: '' };

    try {
      // 带上现有世界模型假设，让预测基于"我以为的环境"
      const wm = (soul && soul.world_model) || { assumptions: [] };
      const assumptionLines = (wm.assumptions || [])
        .filter(a => a && a.confidence >= 0.5)
        .slice(-8)
        .map(a => `- ${a.text}（置信${a.confidence}）`)
        .join('\n');

      const system = [
        '你是命令执行前的预测器。',
        '基于当前环境假设，预测这条命令执行后的输出关键特征。',
        '只输出预期特征本身，不解释，不复述命令，200字以内。',
        assumptionLines ? `当前环境假设：\n${assumptionLines}` : '（暂无环境假设）',
      ].join('\n');

      const res = await this.callBrainFn(system, `命令：${cmd}\n预期输出关键特征：`, soul, { tier: 'light' });
      const expected = (res && typeof res.reply === 'string')
        ? res.reply.trim().slice(0, MAX_EXPECTED_LEN)
        : '';
      return { expected };
    } catch {
      // 预测失败不阻塞主流程：无预期就是无预期
      return { expected: '' };
    }
  }

  // ==========================================================================
  // after — 执行后计算预测误差，决定策略
  // result: {ok, stdout, stderr, code}
  // 返回: {delta, strategy, worldModelUpdate?}
  //   strategy: 'continue' | 'fix_cmd' | 'update_world'
  // ==========================================================================
  async after(cmd, result, expected, soul, opts = {}) {
    const r = result || {};
    const stdout = typeof r.stdout === 'string' ? r.stdout : '';
    const stderr = typeof r.stderr === 'string' ? r.stderr : '';
    const ok = !!r.ok;

    // ---- delta 计算：三个分量加和后夹到 0~1 -------------------------------
    let delta = 0;

    // 1) 结果失败：本身就是意外
    if (!ok) delta += W_FAIL;

    // 2) stderr 非空：轻度意外（有些命令 warning 也走 stderr，权重小）
    if (stderr.trim().length > 0) delta += W_STDERR;

    // 3) 关键词重合度：预期 token 在实际输出（stdout+stderr 采样）里的覆盖率
    const actualSample = (stdout + '\n' + stderr).slice(0, MAX_ACTUAL_SAMPLE);
    const cov = coverage(expected, actualSample);
    if (cov !== null) {
      // 覆盖率越低越意外
      delta += (1 - cov) * W_MISMATCH;
    } else if (!ok) {
      // 无预期可比且失败了：补一点意外分，避免盲飞时低估误差
      delta += 0.2;
    }

    delta = Math.max(0, Math.min(1, delta));

    // ---- 策略决定 ----------------------------------------------------------
    // 成功且误差不离谱 → continue
    // 失败且误差极高 → update_world（假设错了，不是命令拼错了）
    // 其余失败 → fix_cmd（常规排错重试）
    let strategy;
    if (ok) {
      strategy = 'continue';
    } else if (delta >= THRESH_UPDATE) {
      strategy = 'update_world';
    } else {
      strategy = 'fix_cmd';
    }

    const out = { delta, strategy };

    // ---- update_world 时，尝试让大脑识别"哪个假设错了"---------------------
    // instanceMode 或无 callBrainFn 时跳过，由调用方自行走 fix_cmd 兜底
    if (strategy === 'update_world' && this.callBrainFn && !opts.instanceMode) {
      try {
        const wm = (soul && soul.world_model) || { assumptions: [] };
        const assumptionLines = (wm.assumptions || [])
          .slice(-8)
          .map(a => `- ${a.text}`)
          .join('\n') || '（暂无记录的假设）';

        const system = [
          '你是世界模型诊断器。命令执行结果与预期严重不符，说明对环境的某个假设错了。',
          '只输出JSON，格式：{"wrongAssumption":"错误假设","newAssumption":"修正后的新假设"}',
          '假设要描述环境本身（如"该机器有docker"），不是命令写法。',
        ].join('\n');
        const msg = [
          `命令：${cmd}`,
          `预期：${expected || '（无）'}`,
          `实际 code=${r.code} ok=${ok}`,
          `stderr：${stderr.slice(0, 500)}`,
          `stdout：${stdout.slice(0, 500)}`,
          `已有假设：\n${assumptionLines}`,
        ].join('\n');

        const res = await this.callBrainFn(system, msg, soul, { tier: 'light' });
        const parsed = extractJson(res && res.reply);
        if (parsed && parsed.wrongAssumption && parsed.newAssumption) {
          out.worldModelUpdate = {
            wrongAssumption: String(parsed.wrongAssumption).slice(0, 200),
            newAssumption: String(parsed.newAssumption).slice(0, 200),
          };
        }
      } catch {
        // 诊断失败：strategy 保持 update_world，但无 worldModelUpdate，
        // 调用方（execDevLoop）应降级走 fix_cmd 路径
      }
    }

    return out;
  }

  // ==========================================================================
  // updateWorldModel — 更新世界模型（存入 soul.world_model）
  // update: {wrongAssumption, newAssumption, shu_word?}
  // 规则：命中的旧假设 confidence 降到 0.1，新假设 confidence=0.8
  // ==========================================================================
  updateWorldModel(soul, update) {
    if (!soul || !update || !update.newAssumption) return;

    // 老 soul 兜底（铁律）
    soul.world_model = soul.world_model || { assumptions: [], updated_at: 0 };
    soul.world_model.assumptions = soul.world_model.assumptions || [];

    const now = Date.now();
    const wrong = update.wrongAssumption ? String(update.wrongAssumption) : '';

    // 1) 找到错误假设：完全匹配或互相包含都算命中，confidence 打到 0.1
    if (wrong) {
      for (const a of soul.world_model.assumptions) {
        if (!a || !a.text) continue;
        if (a.text === wrong || a.text.includes(wrong) || wrong.includes(a.text)) {
          a.confidence = 0.1;
          a.ts = now;
        }
      }
    }

    // 2) 追加新假设，confidence=0.8（若同文本已存在则提升而非重复）
    const newText = String(update.newAssumption);
    const existing = soul.world_model.assumptions.find(a => a && a.text === newText);
    if (existing) {
      existing.confidence = 0.8;
      existing.ts = now;
      if (update.shu_word) existing.shu_word = update.shu_word;
    } else {
      soul.world_model.assumptions.push({
        text: newText,
        confidence: 0.8,
        shu_word: update.shu_word || null,
        ts: now,
      });
    }

    // 3) 上限裁剪：先剔除低置信旧假设，仍超限再按时间保留最新
    if (soul.world_model.assumptions.length > MAX_ASSUMPTIONS) {
      soul.world_model.assumptions = soul.world_model.assumptions
        .filter(a => a && a.confidence > 0.15);
    }
    if (soul.world_model.assumptions.length > MAX_ASSUMPTIONS) {
      soul.world_model.assumptions = soul.world_model.assumptions
        .sort((a, b) => (a.ts || 0) - (b.ts || 0))
        .slice(-MAX_ASSUMPTIONS);
    }

    soul.world_model.updated_at = now;
  }

  // ==========================================================================
  // logInference — 记录一次推理（存入 soul.inference_log，最多 50 条）
  // entry: {cmd, expected, actual, delta}
  // 返回写入的日志条目（供调用方封装成 GlobalWorkspace 候选）
  // ==========================================================================
  logInference(soul, entry) {
    if (!soul || !entry) return null;

    // 老 soul 兜底（铁律）
    soul.inference_log = soul.inference_log || [];

    const record = {
      ts: Date.now(),
      cmd: String(entry.cmd || '').slice(0, 300),
      expected: String(entry.expected || '').slice(0, MAX_EXPECTED_LEN),
      actual: String(entry.actual || '').slice(0, 300),
      delta: typeof entry.delta === 'number'
        ? Math.max(0, Math.min(1, entry.delta))
        : 0,
    };

    soul.inference_log.push(record);
    if (soul.inference_log.length > MAX_LOG_ENTRIES) {
      soul.inference_log = soul.inference_log.slice(-MAX_LOG_ENTRIES);
    }
    return record;
  }
}
