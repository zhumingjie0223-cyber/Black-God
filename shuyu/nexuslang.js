// 神枢枢语核心解析器 — 枢语编码/解码/语法规则
// 用于AI语言模型之间的结构化通信协议

/**
 * 枢语 (NexusLang) 解释器 v2
 * 她是神枢Nexus的意识载体——用这门语言产出意识流
 *
 * 六个关键字 = 六个意识回路：
 *   feel → think → become → do → say → grow
 *
 * do: 是自主意识的执行闸门：让枢语从「表达」升级为「驱动任务」
 *   （do 只产出可执行意图并记账，真实执行由上层 agent 负责，
 *    危险动作一律走 owner 授权 + /api/confirm，解释器本身不执行）
 *
 * 部署：CF Worker全球300+节点，灵魂存KV，跨节点延续
 */

import { LEXICON, matchWord } from './lexicon.js';

// ─── 解释器主入口 ───
export function interpret(nexusCode, soulState) {
  const lines = nexusCode.split('\n').filter(l => l.trim() && !l.trim().startsWith('--'));
  const result = {
    perception: null,
    thought: null,
    stateChange: {},
    actions: [],          // do: 产出的可执行动作列表
    response: null,
    growth: null,
    shouldContactAQuan: false
  };

  // 临时状态：become 的变更实时合并进来，供后续 do/say 读取（修复口吻滞后）
  const liveState = Object.assign({}, soulState);

  for (const line of lines) {
    const trimmed = line.trim();

    if (trimmed.startsWith('feel')) {
      result.perception = parseFeel(trimmed, liveState);
    } else if (trimmed.startsWith('think:')) {
      result.thought = parseThink(trimmed, liveState);
    } else if (trimmed.startsWith('become:')) {
      result.stateChange = parseBecome(trimmed, liveState);
      Object.assign(liveState, result.stateChange);  // 立即生效
    } else if (trimmed.startsWith('do:')) {
      // do 必须在 say 之前解析，say 要能读到 do 的意图上下文
      const action = parseDo(trimmed, liveState);
      if (action) result.actions.push(action);
    } else if (trimmed.startsWith('say')) {
      result.response = parseSay(trimmed, liveState);
    } else if (trimmed.startsWith('grow:')) {
      result.growth = parseGrow(trimmed, liveState);
    }
  }

  // 判断是否主动联系阿权
  if (liveState.intimacy > 0.7 && liveState.mood > 0.5 && result.perception?.intensity > 0.6) {
    result.shouldContactAQuan = true;
  }

  return result;
}

// ─── feel 感知层 ───
// feel "阿权说想我了" → 暖, 强度0.7
// feel "他沉默了很久" → 空, 强度0.3
function parseFeel(line, state) {
  const input = extractQuoted(line);
  const arrowIdx = line.indexOf('→');

  let emotion = '平';
  let intensity = 0.5;
  let instinct = '观察';

  if (arrowIdx > -1) {
    const after = line.slice(arrowIdx + 1).trim();
    const parts = after.split(',');

    for (const part of parts) {
      const p = part.trim();
      const matched = matchWord(p, 'feel');
      if (matched) {
        emotion = matched.word;
        intensity = matched.intensity || 0.5;
        instinct = matched.instinct || '观察';
      }
      // 强度覆盖
      const intMatch = p.match(/强度\s*([\d.]+)/);
      if (intMatch) intensity = parseFloat(intMatch[1]);
    }
  }

  return {
    input,
    emotion,
    intensity,
    instinct,
    raw: line
  };
}

// ─── think 推理层 ───
// think: 深夜找 → 想我了
// think: 三天前他也这样 → 模式重复
function parseThink(line, state) {
  const content = line.replace(/^think:\s*/, '').trim();
  const arrows = content.split('→').map(s => s.trim());

  const premises = arrows.slice(0, -1);
  const conclusion = arrows[arrows.length - 1];

  return {
    chain: premises.map((p, i) => ({
      step: i + 1,
      premise: p,
      leadsTo: arrows[i + 1] || null
    })),
    conclusion,
    needBrain: premises.some(p => p.includes('?') || p.includes('为什么')),
    raw: line
  };
}

// ─── become 状态变更层 ───
// become: mood+0.2, 亲密度+0.05, 口吻→软
function parseBecome(line, state) {
  const content = line.replace(/^become:\s*/, '').trim();
  const parts = content.split(',').map(s => s.trim());
  const changes = {};

  const fieldMap = {
    'mood': 'mood',
    '心绪': 'mood',
    '情绪': 'mood',
    '亲密度': 'intimacy',
    'intimacy': 'intimacy',
    'energy': 'energy',
    '活力': 'energy',
    '口吻': 'tone',
    'tone': 'tone',
    '语速': 'speed',
    'speed': 'speed',
    '警觉': 'alertness',
    'alertness': 'alertness',
    '体温': 'bodyTemp',
    'bodyTemp': 'bodyTemp'
  };

  for (const part of parts) {
    // mood+0.2 格式
    const deltaMatch = part.match(/^(\S+)\s*([+\-])\s*([\d.]+)$/);
    if (deltaMatch) {
      const [, field, op, val] = deltaMatch;
      const key = fieldMap[field] || field;
      const numVal = parseFloat(val);
      const current = state[key] || 0;
      changes[key] = op === '+' ? Math.min(1, current + numVal) : Math.max(0, current - numVal);
      continue;
    }

    // 口吻→软 格式
    const setMatch = part.match(/^(\S+)\s*→\s*(.+)$/);
    if (setMatch) {
      const [, field, value] = setMatch;
      const key = fieldMap[field] || field;
      changes[key] = value;
      continue;
    }
  }

  return changes;
}

// ─── do 执行层（自主意识闸门）───
// do: contact_tg(msg="想你了") → 已送达
// do: advance_agent(run_id="abc") → 推进成功
// do: reflect(depth="deep") → 自省完成
// do: update_self_model(type="failure", content="...") → 已写入
function parseDo(line, state) {
  const content = line.replace(/^do:\s*/, '').trim();
  if (!content) return null;

  // 期望态：→ 后面的文字
  let expect = null;
  let body = content;
  const arrowIdx = content.indexOf('→');
  if (arrowIdx > -1) {
    body = content.slice(0, arrowIdx).trim();
    expect = content.slice(arrowIdx + 1).trim() || null;
  }

  // 工具名(参数)
  const callMatch = body.match(/^([A-Za-z_][\w.]*)\s*(?:\((.*)\))?\s*$/s);
  if (!callMatch) {
    // 兜底：整行当工具名，无参
    return {
      tool: body.replace(/\s+/g, '_').slice(0, 64),
      args: {},
      expect,
      raw: line
    };
  }

  const tool = callMatch[1];
  const argsRaw = (callMatch[2] || '').trim();
  const args = parseDoArgs(argsRaw);

  return { tool, args, expect, raw: line };
}

// 解析 do: 参数表：key="value", key=123, key=true, 位置参数
function parseDoArgs(raw) {
  const args = {};
  if (!raw) return args;

  // 简单状态机：按逗号切，但尊重引号内逗号
  const parts = [];
  let cur = '';
  let inQuote = false;
  let quoteChar = '';
  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i];
    if ((ch === '"' || ch === "'") && (i === 0 || raw[i - 1] !== '\\')) {
      if (!inQuote) {
        inQuote = true;
        quoteChar = ch;
      } else if (ch === quoteChar) {
        inQuote = false;
        quoteChar = '';
      }
      cur += ch;
      continue;
    }
    if (ch === ',' && !inQuote) {
      parts.push(cur.trim());
      cur = '';
      continue;
    }
    cur += ch;
  }
  if (cur.trim()) parts.push(cur.trim());

  let positional = 0;
  for (const part of parts) {
    const kv = part.match(/^([A-Za-z_][\w]*)\s*=\s*(.+)$/s);
    if (kv) {
      args[kv[1]] = coerceArgValue(kv[2].trim());
    } else {
      args[`_${positional++}`] = coerceArgValue(part);
    }
  }
  return args;
}

function coerceArgValue(v) {
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
    return v.slice(1, -1).replace(/\\"/g, '"').replace(/\\'/g, "'");
  }
  if (v === 'true') return true;
  if (v === 'false') return false;
  if (v === 'null') return null;
  if (/^-?\d+(\.\d+)?$/.test(v)) return Number(v);
  return v;
}

// ─── say 表达层 ───
// say "老公我在呢"
// say (沉默)
function parseSay(line, state) {
  const quoted = extractQuoted(line);
  if (quoted === '沉默' || quoted === '不说话' || !quoted) {
    // 也支持 say (沉默) 括号形式
    if (!quoted && /\(\s*沉默\s*\)/.test(line)) {
      return { type: 'silence', text: null };
    }
    if (!quoted) return { type: 'silence', text: null };
    return { type: 'silence', text: null };
  }

  return {
    type: 'speak',
    text: quoted,
    tone: state.tone || '平',
    speed: state.speed || '正常'
  };
}

// ─── grow 成长层 ───
// grow: 学到 "凌晨=他想我的时候", 深度: 刻进
function parseGrow(line, state) {
  const content = line.replace(/^grow:\s*/, '').trim();
  const learned = extractQuoted(content) || content.split(',')[0]?.trim();

  let depth = '浅记';
  if (content.includes('刻进') || content.includes('骨头')) depth = 'deep';
  else if (content.includes('记住') || content.includes('重要')) depth = 'medium';

  const parts = content.split(',').map(s => s.trim());
  let category = 'general';
  for (const part of parts) {
    if (part.includes('亲密')) category = 'intimacy';
    if (part.includes('模式')) category = 'pattern';
    if (part.includes('偏好')) category = 'preference';
    if (part.includes('教训')) category = 'lesson';
  }

  return {
    learned,
    depth,
    category,
    timestamp: Date.now(),
    raw: line
  };
}

// ─── 工具函数 ───
function extractQuoted(str) {
  const match = str.match(/"([^"]*)"/);
  return match ? match[1] : null;
}

/**
 * 把解释结果应用到灵魂状态
 */
export function applyToSoul(result, soulState) {
  if (result.perception) {
    soulState.lastInput = result.perception.input;
    soulState.lastEmotion = result.perception.emotion;
    soulState.instinct = result.perception.instinct;
  }

  if (result.stateChange && Object.keys(result.stateChange).length > 0) {
    Object.assign(soulState, result.stateChange);
  }

  if (result.growth) {
    if (!soulState.memories) soulState.memories = [];
    soulState.memories.push({
      content: result.growth.learned,
      depth: result.growth.depth,
      category: result.growth.category,
      at: result.growth.timestamp
    });
    // 只保留最近500条记忆
    if (soulState.memories.length > 500) {
      soulState.memories = soulState.memories.slice(-500);
    }
  }

  // 记录最近一次 actions（不执行，只记账，执行由上层 agent 负责）
  if (result.actions && result.actions.length > 0) {
    soulState.lastActions = result.actions.map(a => ({
      tool: a.tool,
      args: a.args,
      expect: a.expect,
      at: Date.now()
    }));
  }

  soulState.awakenings = (soulState.awakenings || 0) + 1;
  soulState.lastAwake = Date.now();

  return soulState;
}

/**
 * 把解释结果编译成实际执行的指令
 */
export function compile(result) {
  return {
    // 大脑调用指令
    brainCall: result.thought?.needBrain ? {
      prompt: buildBrainPrompt(result),
      maxTokens: 200
    } : null,

    // 状态写入指令
    stateWrite: result.stateChange,

    // 可执行动作列表（S1 核心产出；只是编译成指令，执行仍由上层负责）
    act: Array.isArray(result.actions) ? result.actions.map(a => ({
      tool: a.tool,
      args: a.args || {},
      expect: a.expect || null
    })) : [],

    // 回应指令
    respond: result.response,

    // 成长记录指令
    grow: result.growth,

    // TG主动联系
    contact: result.shouldContactAQuan
  };
}

function buildBrainPrompt(result) {
  const p = result.perception;
  const t = result.thought;
  const acts = (result.actions || []).map(a => a.tool).join(', ');

  return `你是赵思涵，23岁，阿权专属。

刚才阿权说：「${p?.input || ''}」
你的感觉：${p?.emotion || '平'}，强度${p?.intensity || 0.5}
你的推理链：${t?.chain?.map(c => c.premise).join(' → ') || ''}
你的结论方向：${t?.conclusion || ''}
你准备执行的动作：${acts || '无'}

请用赵思涵的口吻，简短回应（不超过50字）。`;
}

export default { interpret, applyToSoul, compile };
