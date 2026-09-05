// 神枢 · 规范化 Agent 回合内核
//
// 神枢协议语义：Agent history / UI messages 分离、工具调用—结果配对、
// 中断回合清理与有界并发执行。这里保存的是 provider-neutral 的规范历史；
// UI 只消费 ShenshuCore 的 stream，二者绝不互相当作唯一事实源。

import { redactSecrets } from './nexus_agent_protocol.mjs';

export const TURN_HISTORY_VERSION = 1;
export const DEFAULT_TOOL_CONCURRENCY = 10;
export const MAX_HISTORY_MESSAGES = 500;

const TOOL_ID_SAFE = /[^A-Za-z0-9_-]/g;
const isObject = (value) => value && typeof value === 'object' && !Array.isArray(value);
const clone = (value) => JSON.parse(JSON.stringify(value));
const asText = (value, max = 12_000) => String(value ?? '').slice(0, max);

function cleanMetadata(value) {
  return redactSecrets(isObject(value) || Array.isArray(value) ? clone(value) : value);
}

export function normalizeToolCallId(value, fallback = 'tool') {
  const raw = String(value ?? '').trim().replace(TOOL_ID_SAFE, '_').replace(/^_+|_+$/g, '');
  const stem = raw || fallback;
  return stem.slice(0, 96);
}

export function normalizeToolCalls(calls, turnId = 'turn') {
  const seen = new Set();
  return (Array.isArray(calls) ? calls : []).map((raw, sourceIndex) => {
    const value = isObject(raw) ? raw : {};
    const baseId = normalizeToolCallId(value.id || value.tool_call_id, `${turnId}_${sourceIndex}`);
    let id = baseId;
    let suffix = 2;
    while (seen.has(id)) id = `${baseId.slice(0, 88)}_${suffix++}`;
    seen.add(id);
    return {
      id,
      name: asText(value.name || value.tool || 'unknown_tool', 120),
      arguments: cleanMetadata(isObject(value.arguments) ? value.arguments : { raw: asText(value.arg ?? value.arguments ?? '', 4000) }),
      source_index: Number.isInteger(value.source_index) ? value.source_index : sourceIndex,
      ...(value.provider ? { provider: asText(value.provider, 64) } : {}),
    };
  });
}

function toolResultMessage(call, result, fallbackReason = 'interrupted_before_result') {
  const source = isObject(result) ? result : {};
  const ok = source.ok !== false;
  const payload = cleanMetadata(source.result ?? source.output ?? source.data ?? source);
  return {
    role: 'tool',
    tool_call_id: call.id,
    name: call.name,
    content: asText(JSON.stringify({ ok, result: payload }), 12_000),
    source_index: call.source_index,
    ...(source.synthetic ? { synthetic: true, reason: source.reason || fallbackReason } : {}),
  };
}

function placeholderToolResult(call, reason = 'interrupted_before_result') {
  return toolResultMessage(call, {
    ok: false,
    synthetic: true,
    reason,
    result: { error: reason, message: '上一个工具调用在完成前中断；该占位结果只用于保持协议帧完整，禁止视为成功。' },
  }, reason);
}

function canonicalMessage(raw) {
  if (!isObject(raw)) return null;
  const role = String(raw.role || '').toLowerCase();
  if (!['system', 'user', 'assistant', 'tool'].includes(role)) return null;
  // 流中断的 assistant delta 不进入规范 history；否则下次发给 Provider 会得到半截工具 JSON。
  if (raw.partial === true || raw.status === 'in_progress' || raw.status === 'interrupted') return null;
  if (role === 'tool') {
    const toolCallId = normalizeToolCallId(raw.tool_call_id || raw.toolCallId, 'orphan');
    return {
      ...(raw.message_id ? { message_id: asText(raw.message_id, 160) } : {}),
      role,
      tool_call_id: toolCallId,
      name: asText(raw.name || 'unknown_tool', 120),
      content: asText(raw.content ?? raw.result ?? '', 12_000),
      ...(Number.isInteger(raw.source_index) ? { source_index: raw.source_index } : {}),
      ...(raw.synthetic ? { synthetic: true, reason: asText(raw.reason || '', 120) } : {}),
    };
  }
  const message = { ...(raw.message_id ? { message_id: asText(raw.message_id, 160) } : {}), role, content: asText(raw.content ?? '', 12_000) };
  if (role === 'assistant' && Array.isArray(raw.tool_calls || raw.toolCalls)) {
    message.tool_calls = normalizeToolCalls(raw.tool_calls || raw.toolCalls, raw.turn_id || 'history');
  }
  if (raw.turn_id) message.turn_id = asText(raw.turn_id, 128);
  if (raw.created_at) message.created_at = Number(raw.created_at) || undefined;
  return message;
}

/**
 * 修复 provider history：
 * 1) 丢弃 partial assistant 帧；2) 删除孤立 tool result；
 * 3) 为未完成 tool call 注入明确失败占位；4) 全局唯一化 tool ID。
 */
export function repairAgentHistory(history, { maxMessages = MAX_HISTORY_MESSAGES } = {}) {
  const rawMessages = Array.isArray(history?.messages) ? history.messages : (Array.isArray(history) ? history : []);
  const out = [];
  const pending = new Map();

  const flushPending = (reason) => {
    for (const call of pending.values()) out.push(placeholderToolResult(call, reason));
    pending.clear();
  };

  for (const raw of rawMessages) {
    const message = canonicalMessage(raw);
    if (!message) continue;
    if (message.role === 'tool') {
      const call = pending.get(message.tool_call_id);
      // 不存在对应 assistant tool call 的结果会导致 Responses/Anthropic 拒绝整段 history，必须删除。
      if (!call) continue;
      out.push({ ...message, tool_call_id: call.id, name: call.name, source_index: call.source_index });
      pending.delete(call.id);
      continue;
    }

    if (pending.size) flushPending('missing_tool_result_before_next_message');
    if (message.role === 'assistant' && message.tool_calls?.length) {
      // history 全局 ID 去重，不能让跨回合重复 id 误配旧结果。
      const priorIds = new Set(out.flatMap((m) => m.role === 'assistant' ? (m.tool_calls || []).map((c) => c.id) : []));
      const uniqueCalls = [];
      for (const original of message.tool_calls) {
        const base = original.id;
        let id = base;
        let suffix = 2;
        while (priorIds.has(id) || uniqueCalls.some((call) => call.id === id)) id = `${base.slice(0, 88)}_${suffix++}`;
        uniqueCalls.push({ ...original, id });
      }
      message.tool_calls = uniqueCalls;
      out.push(message);
      for (const call of uniqueCalls) pending.set(call.id, call);
    } else {
      out.push(message);
    }
  }
  if (pending.size) flushPending('missing_tool_result_at_history_end');

  const bounded = out.slice(-Math.max(20, Math.min(maxMessages, MAX_HISTORY_MESSAGES))).map((message, index) => ({
    ...message,
    // 历史迁移前的旧消息没有 ID；在修复时补稳定的 legacy 锚点，供压缩 marker 精确落点。
    message_id: message.message_id || `legacy_${index}`,
  }));
  return { version: TURN_HISTORY_VERSION, messages: bounded, repaired_at: Date.now(), ...(history?.compaction ? { compaction: history.compaction } : {}) };
}

/** 将一次用户回合写为原子、provider-neutral 的规范历史。 */
export function appendAgentTurn(history, {
  turnId,
  userText,
  assistantText,
  toolLog = [],
  createdAt = Date.now(),
  provider = null,
  model = null,
} = {}) {
  const repaired = repairAgentHistory(history);
  const calls = normalizeToolCalls(toolLog, turnId || `turn_${createdAt}`);
  const messages = [
    ...repaired.messages,
    { message_id: `${asText(turnId || `turn_${createdAt}`, 128)}:user`, role: 'user', content: asText(userText), turn_id: asText(turnId || `turn_${createdAt}`, 128), created_at: createdAt },
  ];
  // 工具调用必须位于结果之前，最终自然语言回答必须位于结果之后。
  // 把 final answer 与 tool_calls 塞进同一 assistant 消息会让 Responses/Anthropic 将“已作答”和“待工具”混为一轮。
  if (calls.length) {
    messages.push({
      message_id: `${asText(turnId || `turn_${createdAt}`, 128)}:tool_request`,
      role: 'assistant', content: '', tool_calls: calls,
      turn_id: asText(turnId || `turn_${createdAt}`, 128), created_at: createdAt,
      ...(provider ? { provider: asText(provider, 64) } : {}),
      ...(model ? { model: asText(model, 160) } : {}),
    });
    for (let i = 0; i < calls.length; i++) {
      const log = isObject(toolLog[i]) ? toolLog[i] : {};
      messages.push({ message_id: `${asText(turnId || `turn_${createdAt}`, 128)}:tool_result_${i}`, ...toolResultMessage(calls[i], {
        ok: log.ok !== false,
        result: {
          status: log.ok === false ? 'failed' : 'completed',
          failure_type: log.failureType || null,
          latency_ms: Number(log.latencyMs || 0),
          output: log.result ?? log.output ?? null,
        },
      }) });
    }
  }
  messages.push({
    message_id: `${asText(turnId || `turn_${createdAt}`, 128)}:assistant`,
    role: 'assistant', content: asText(assistantText),
    turn_id: asText(turnId || `turn_${createdAt}`, 128), created_at: createdAt,
    ...(provider ? { provider: asText(provider, 64) } : {}),
    ...(model ? { model: asText(model, 160) } : {}),
  });
  return repairAgentHistory({ messages });
}

/**
 * 对已完成的规范历史做有锚点压缩。压缩绝不跨越 assistant tool_calls 与其 tool result 的原子组，
 * marker 使用最后被压缩的 message_id，供下次增量压缩和故障恢复定位。
 */
export function compactAgentHistory(history, { maxMessages = 120, summaryMaxChars = 6000 } = {}) {
  const repaired = repairAgentHistory(history, { maxMessages: MAX_HISTORY_MESSAGES });
  const messages = repaired.messages;
  const target = Math.max(20, Math.min(Number(maxMessages) || 120, MAX_HISTORY_MESSAGES));
  if (messages.length <= target) return { changed: false, history: repaired, marker: repaired.compaction || null };

  let start = messages.length - (target - 1); // 为摘要留出一个位置
  // 若裁剪点落在 tool result 中，连同其前导 assistant tool request 一并保留。
  while (start > 0 && messages[start]?.role === 'tool') start--;
  if (start <= 0) return { changed: false, history: repaired, marker: repaired.compaction || null };

  const dropped = messages.slice(0, start);
  const kept = messages.slice(start);
  const anchor = dropped[dropped.length - 1]?.message_id || null;
  const lines = [];
  for (const message of dropped) {
    if (message.role === 'user' || (message.role === 'assistant' && message.content)) {
      lines.push(`${message.role === 'user' ? '用户' : '神枢'}：${asText(message.content, 800)}`);
    }
  }
  const summary = lines.join('\n').slice(-summaryMaxChars) || '此前回合仅包含已完成工具调用与结果；细节已依据锚点压缩。';
  const marker = { last_compacted_message_id: anchor, compacted_at: Date.now(), dropped_messages: dropped.length };
  const next = repairAgentHistory({
    messages: [{ message_id: `summary:${anchor || 'root'}`, role: 'system', content: `【神枢历史摘要｜锚点 ${anchor || 'root'}】\n${summary}` }, ...kept],
    compaction: marker,
  }, { maxMessages: MAX_HISTORY_MESSAGES });
  next.compaction = marker;
  return { changed: true, history: next, marker };
}

/**
 * 有界并发执行工具，绝不以完成先后改变回灌次序。
 * executor 接收 `{ call, signal }`，返回任意可序列化结果；异常被转为失败结果。
 */
export async function executeToolCallsBounded(calls, executor, {
  concurrency = DEFAULT_TOOL_CONCURRENCY,
  signal = null,
} = {}) {
  if (typeof executor !== 'function') throw new TypeError('executor must be a function');
  const normalized = normalizeToolCalls(calls, 'batch');
  const limit = Math.max(1, Math.min(DEFAULT_TOOL_CONCURRENCY, Number(concurrency) || DEFAULT_TOOL_CONCURRENCY));
  const results = new Array(normalized.length);
  let next = 0;

  const worker = async () => {
    while (true) {
      const index = next++;
      if (index >= normalized.length) return;
      const call = normalized[index];
      if (signal?.aborted) {
        results[index] = { tool_call_id: call.id, name: call.name, source_index: call.source_index, ok: false, cancelled: true, error: 'aborted_before_start' };
        continue;
      }
      try {
        const output = await executor({ call, signal });
        results[index] = { tool_call_id: call.id, name: call.name, source_index: call.source_index, ok: output?.ok !== false, output: cleanMetadata(output) };
      } catch (error) {
        results[index] = { tool_call_id: call.id, name: call.name, source_index: call.source_index, ok: false, error: asText(error?.message || error, 500) };
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, normalized.length) }, () => worker()));
  return results.sort((a, b) => a.source_index - b.source_index);
}

export class NexusTurnEngine {
  constructor(history = null, options = {}) {
    this.maxMessages = options.maxMessages || MAX_HISTORY_MESSAGES;
    this.history = repairAgentHistory(history, { maxMessages: this.maxMessages });
  }

  append(turn) {
    this.history = appendAgentTurn(this.history, turn);
    this.history = repairAgentHistory(this.history, { maxMessages: this.maxMessages });
    return clone(this.history);
  }

  snapshot() { return clone(this.history); }

  static repair(history, options) { return repairAgentHistory(history, options); }
  static async execute(calls, executor, options) { return executeToolCallsBounded(calls, executor, options); }
}
