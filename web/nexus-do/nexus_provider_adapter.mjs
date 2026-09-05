// 神枢 · 多模型协议适配层
//
// 以 provider-neutral agent_history_v1 为唯一历史输入，统一 OpenAI Chat/Responses、Anthropic、Gemini。
// 适配器不执行工具，不保存明文凭据，也不把 provider 私有 reasoning 泄露给其他模型。

import { normalizeToolCallId, repairAgentHistory } from './nexus_turn_engine.mjs';

const asText = (value, max = 16_000) => String(value ?? '').slice(0, max);
const isObject = (value) => value && typeof value === 'object' && !Array.isArray(value);
// 退避等待：取消信号到来时提前结束（resolve 而非 reject），由调用方循环开头统一判定 aborted，
// 避免在 catch 分支里的 await 抛出未捕获异常。
const sleep = (ms, signal) => new Promise((resolve) => {
  if (!(ms > 0) || signal?.aborted) return resolve();
  const timer = setTimeout(() => {
    signal?.removeEventListener?.('abort', onAbort);
    resolve();
  }, ms);
  const onAbort = () => {
    clearTimeout(timer);
    resolve();
  };
  signal?.addEventListener?.('abort', onAbort, { once: true });
});
const asNonNegInt = (value, fallback = 0) => {
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
};
const parseRetryAfterMs = (value) => {
  const raw = asText(value || '', 80).trim();
  if (!raw) return null;
  if (/^\d+(?:\.\d+)?$/.test(raw)) return Math.max(0, Math.round(Number(raw) * 1000));
  const at = Date.parse(raw);
  return Number.isFinite(at) ? Math.max(0, at - Date.now()) : null;
};

export function sanitizeToolId(value, fallback = 'tool') {
  const raw = asText(value || fallback, 128).replace(/[^A-Za-z0-9_-]/g, '_').replace(/^_+|_+$/g, '');
  return (raw || fallback).slice(0, 64);
}

export function nonEmptyFinishReason(value) {
  const reason = asText(value || '', 80).trim();
  return reason || null;
}

/** Provider 私有推理仅允许回显给同一 provider，并以 opaque envelope 保存。 */
export class ReasoningEcho {
  constructor() { this.entries = []; }
  record({ provider, encrypted = null, text = null, itemId = null } = {}) {
    if (!provider || (!encrypted && !text)) return null;
    const entry = { provider: asText(provider, 40), item_id: itemId ? asText(itemId, 128) : null, encrypted: encrypted ? asText(encrypted, 64_000) : null, text: encrypted ? null : asText(text, 16_000) };
    this.entries.push(entry);
    if (this.entries.length > 64) this.entries.shift();
    return { ...entry };
  }
  forProvider(provider) { return this.entries.filter((entry) => entry.provider === provider).map((entry) => ({ ...entry })); }
}

function toolIdMap(history) {
  const map = new Map();
  for (const message of history.messages) {
    if (message.role !== 'assistant') continue;
    for (const call of message.tool_calls || []) map.set(call.id, sanitizeToolId(call.id));
  }
  return map;
}

export function historyToOpenAIChat(history) {
  const repaired = repairAgentHistory(history);
  const ids = toolIdMap(repaired);
  return repaired.messages.map((message) => {
    if (message.role === 'tool') return { role: 'tool', tool_call_id: ids.get(message.tool_call_id) || sanitizeToolId(message.tool_call_id), content: message.content };
    if (message.role === 'assistant' && message.tool_calls?.length) {
      return {
        role: 'assistant', content: message.content || null,
        tool_calls: message.tool_calls.map((call) => ({
          id: ids.get(call.id) || sanitizeToolId(call.id), type: 'function',
          function: { name: sanitizeToolId(call.name, 'tool'), arguments: JSON.stringify(call.arguments || {}) },
        })),
      };
    }
    return { role: message.role, content: message.content };
  });
}

/** Responses API 不允许孤立 function_call_output；repairAgentHistory 已先修复，再做一次配对校验。 */
export function historyToOpenAIResponses(history) {
  const repaired = repairAgentHistory(history);
  const ids = toolIdMap(repaired);
  const items = [];
  const pending = new Set();
  for (const message of repaired.messages) {
    if (message.role === 'user' || message.role === 'system') items.push({ role: message.role, content: [{ type: 'input_text', text: message.content }] });
    else if (message.role === 'assistant') {
      if (message.content) items.push({ role: 'assistant', content: [{ type: 'output_text', text: message.content }] });
      for (const call of message.tool_calls || []) {
        const callId = ids.get(call.id) || sanitizeToolId(call.id);
        pending.add(callId);
        items.push({ type: 'function_call', call_id: callId, name: sanitizeToolId(call.name, 'tool'), arguments: JSON.stringify(call.arguments || {}) });
      }
    } else if (message.role === 'tool') {
      const callId = ids.get(message.tool_call_id) || sanitizeToolId(message.tool_call_id);
      if (!pending.has(callId)) continue;
      items.push({ type: 'function_call_output', call_id: callId, output: message.content });
      pending.delete(callId);
    }
  }
  return { input: items, complete: pending.size === 0, pending_call_ids: [...pending] };
}

export function historyToAnthropic(history) {
  const repaired = repairAgentHistory(history);
  const ids = toolIdMap(repaired);
  const messages = [];
  for (const message of repaired.messages) {
    if (message.role === 'system') continue;
    if (message.role === 'assistant') {
      const content = [];
      if (message.content) content.push({ type: 'text', text: message.content });
      for (const call of message.tool_calls || []) content.push({ type: 'tool_use', id: ids.get(call.id) || sanitizeToolId(call.id), name: sanitizeToolId(call.name, 'tool'), input: call.arguments || {} });
      messages.push({ role: 'assistant', content: content.length ? content : [{ type: 'text', text: '' }] });
    } else if (message.role === 'tool') {
      messages.push({ role: 'user', content: [{ type: 'tool_result', tool_use_id: ids.get(message.tool_call_id) || sanitizeToolId(message.tool_call_id), content: message.content }] });
    } else messages.push({ role: 'user', content: message.content });
  }
  return messages;
}

export function historyToGemini(history) {
  const repaired = repairAgentHistory(history);
  const contents = [];
  for (const message of repaired.messages) {
    if (message.role === 'system') continue;
    if (message.role === 'assistant') {
      const parts = message.content ? [{ text: message.content }] : [];
      for (const call of message.tool_calls || []) parts.push({ functionCall: { name: sanitizeToolId(call.name, 'tool'), args: call.arguments || {} } });
      contents.push({ role: 'model', parts: parts.length ? parts : [{ text: '' }] });
    } else if (message.role === 'tool') {
      contents.push({ role: 'user', parts: [{ functionResponse: { name: sanitizeToolId(message.name, 'tool'), response: { content: message.content } } }] });
    } else contents.push({ role: 'user', parts: [{ text: message.content }] });
  }
  return contents;
}

function rootFor(base, suffix) {
  const clean = String(base || '').replace(/\/+$/, '');
  return clean.endsWith(suffix) ? clean : clean + suffix;
}

/** 构造可直接 fetch 的 provider 请求；history 必须是过去已完成回合，userInput 为当前输入。 */
export function buildProviderRequest({ provider = 'openai', base, key, model, system = '', userInput = '', history = null, temperature, maxTokens = 1500, apiMode = 'chat' } = {}) {
  const dialect = String(provider || 'openai').toLowerCase();
  const repaired = repairAgentHistory(history);
  const withTemp = typeof temperature === 'number' ? { temperature } : {};
  if (dialect === 'anthropic') {
    const url = rootFor(base, '/v1/messages');
    const oauth = /^sk-ant-oat/i.test(String(key || ''));
    const headers = { 'content-type': 'application/json', 'anthropic-version': '2023-06-01', ...(oauth ? { Authorization: `Bearer ${key}`, 'anthropic-beta': 'oauth-2025-04-20' } : (key ? { 'x-api-key': key } : {})) };
    return { provider: 'anthropic', mode: 'messages', url, headers, body: { model, max_tokens: maxTokens, ...(system ? { system } : {}), messages: [...historyToAnthropic(repaired), { role: 'user', content: asText(userInput) }], ...withTemp } };
  }
  if (dialect === 'gemini' || dialect === 'google') {
    const root = String(base || 'https://generativelanguage.googleapis.com').replace(/\/+$/, '').replace(/\/v1beta.*$/, '');
    return { provider: 'gemini', mode: 'generateContent', url: `${root}/v1beta/models/${encodeURIComponent(model || 'gemini-2.0-flash')}:generateContent?key=${encodeURIComponent(key || '')}`, headers: { 'content-type': 'application/json' }, body: { ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}), contents: [...historyToGemini(repaired), { role: 'user', parts: [{ text: asText(userInput) }] }], generationConfig: { maxOutputTokens: maxTokens, ...withTemp } } };
  }
  const wantsResponses = apiMode === 'responses' || /\/responses$/.test(String(base || ''));
  if (wantsResponses) {
    const root = String(base || '').replace(/\/+$/, '').replace(/\/chat\/completions$/, '');
    const responseHistory = historyToOpenAIResponses(repaired);
    return { provider: 'openai', mode: 'responses', url: rootFor(root, '/responses'), headers: { 'content-type': 'application/json', ...(key ? { Authorization: `Bearer ${key}` } : {}) }, body: { model, ...(system ? { instructions: system } : {}), input: [...responseHistory.input, { role: 'user', content: [{ type: 'input_text', text: asText(userInput) }] }], max_output_tokens: maxTokens, ...withTemp }, protocol: responseHistory };
  }
  return { provider: 'openai', mode: 'chat', url: rootFor(base, '/chat/completions'), headers: { 'content-type': 'application/json', ...(key ? { Authorization: `Bearer ${key}` } : {}) }, body: { model, messages: [...(system ? [{ role: 'system', content: system }] : []), ...historyToOpenAIChat(repaired), { role: 'user', content: asText(userInput) }], max_tokens: maxTokens, ...withTemp } };
}

export function normalizeProviderResponse(provider, data) {
  const dialect = String(provider || 'openai').toLowerCase();
  if (dialect === 'anthropic') return asText((data?.content || []).filter((block) => block?.type === 'text').map((block) => block.text || '').join('')).trim() || null;
  if (dialect === 'gemini' || dialect === 'google') return asText(data?.candidates?.[0]?.content?.parts?.map((part) => part?.text || '').join('')).trim() || null;
  if (data?.output_text) return asText(data.output_text).trim() || null;
  if (Array.isArray(data?.output)) return asText(data.output.flatMap((item) => item?.content || []).filter((part) => part?.type === 'output_text').map((part) => part.text || '').join('')).trim() || null;
  return asText(data?.choices?.[0]?.message?.content || data?.reply || data?.response || '').trim() || null;
}

export function extractProviderUsage(provider, data) {
  const dialect = String(provider || 'openai').toLowerCase();
  const usage = data?.usage || data?.response?.usage || null;
  if (dialect === 'anthropic') {
    const input = Number(usage?.input_tokens || 0);
    const output = Number(usage?.output_tokens || 0);
    const total = Number(usage?.total_tokens || (input + output));
    return (input || output || total) ? { input_tokens: input, output_tokens: output, total_tokens: total } : null;
  }
  if (dialect === 'gemini' || dialect === 'google') {
    const um = data?.usageMetadata || usage || {};
    const input = Number(um.promptTokenCount || um.input_tokens || 0);
    const output = Number(um.candidatesTokenCount || um.output_tokens || 0);
    const total = Number(um.totalTokenCount || um.total_tokens || (input + output));
    return (input || output || total) ? { input_tokens: input, output_tokens: output, total_tokens: total } : null;
  }
  const input = Number(usage?.prompt_tokens || usage?.input_tokens || 0);
  const output = Number(usage?.completion_tokens || usage?.output_tokens || 0);
  const total = Number(usage?.total_tokens || usage?.output_tokens_total || (input + output));
  return (input || output || total) ? { input_tokens: input, output_tokens: output, total_tokens: total } : null;
}

function shouldRetryStatus(status) {
  return [408, 409, 425, 429, 500, 502, 503, 504].includes(Number(status));
}

function shouldRetryError(error) {
  if (!error) return false;
  if (error.name === 'AbortError') return false;
  const s = asText(error?.message || error, 160).toLowerCase();
  return /network|fetch failed|econnreset|etimedout|socket|temporar|unavailable/.test(s);
}

/** 统一执行 provider 请求：超时、有限重试、用量提取。 */
export async function executeProviderJSONRequest({
  request,
  fetchImpl = fetch,
  signal = null,
  timeoutMs = 20_000,
  retries = 0,
  retryBaseMs = 300,
  retryMaxMs = 2_000,
} = {}) {
  const url = request?.url;
  if (!url) return { ok: false, error: 'invalid_request', attempts: 0 };
  const maxRetries = asNonNegInt(retries, 0);
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const ctrl = new AbortController();
    let timedOut = false;
    let timer = null;
    const relayAbort = () => ctrl.abort(signal?.reason);
    if (signal?.aborted) return { ok: false, error: 'aborted', attempts: attempt };
    signal?.addEventListener?.('abort', relayAbort, { once: true });
    try {
      const ms = asNonNegInt(timeoutMs, 20_000);
      if (ms > 0) timer = setTimeout(() => { timedOut = true; ctrl.abort(); }, ms);
      const res = await fetchImpl(url, {
        method: request.method || 'POST',
        headers: request.headers || {},
        body: request.body == null ? undefined : JSON.stringify(request.body),
        signal: ctrl.signal,
      });
      const text = await res.text().catch(() => '');
      let data = null;
      let parseError = null;
      try { data = text ? JSON.parse(text) : null; } catch (error) { data = null; parseError = error; }
      const usage = extractProviderUsage(request.provider, data);
      if (res.ok) {
        const noContent = res.status === 204 || res.status === 205;
        if (!noContent && text.trim() && data == null && parseError) {
          return { ok: false, status: res.status, error: 'invalid_json', data: null, text, usage, attempts: attempt + 1 };
        }
        return { ok: true, status: res.status, data, text, usage, attempts: attempt + 1 };
      }
      const canRetry = attempt < maxRetries && shouldRetryStatus(res.status);
      if (!canRetry) return { ok: false, status: res.status, data, text, usage, attempts: attempt + 1 };
      const retryAfter = parseRetryAfterMs(res.headers?.get?.('retry-after'));
      const delay = retryAfter ?? Math.min(retryMaxMs, retryBaseMs * Math.pow(2, attempt));
      await sleep(delay, signal);
    } catch (error) {
      if (signal?.aborted) return { ok: false, error: 'aborted', attempts: attempt + 1 };
      if (timedOut) return { ok: false, error: 'timeout', attempts: attempt + 1 };
      const canRetry = attempt < maxRetries && shouldRetryError(error);
      if (!canRetry) return { ok: false, error: asText(error?.message || error, 180), attempts: attempt + 1 };
      const delay = Math.min(retryMaxMs, retryBaseMs * Math.pow(2, attempt));
      await sleep(delay, signal);
    } finally {
      if (timer) clearTimeout(timer);
      signal?.removeEventListener?.('abort', relayAbort);
    }
  }
  return { ok: false, error: 'unknown', attempts: 0 };
}

/** 将单个 SSE JSON 帧归一化为神枢事件；调用方可将这些事件转成 WebSocket/SSE。 */
export function normalizeSSEFrame(provider, frame, state = {}) {
  const dialect = String(provider || 'openai').toLowerCase();
  const events = [];
  if (!isObject(frame)) return events;
  const pushUsage = (usage) => { if (usage) events.push({ type: 'usage', usage }); };
  if (dialect === 'anthropic') {
    if (frame.type === 'content_block_delta' && frame.delta?.type === 'text_delta') events.push({ type: 'text_delta', text: frame.delta.text || '' });
    if (frame.type === 'content_block_delta' && frame.delta?.type === 'thinking_delta') events.push({ type: 'reasoning_delta', text: frame.delta.thinking || '' });
    if (frame.type === 'message_delta') { pushUsage(frame.usage); const finish = nonEmptyFinishReason(frame.delta?.stop_reason); if (finish) events.push({ type: 'done', finish_reason: finish }); }
    return events;
  }
  if (dialect === 'gemini' || dialect === 'google') {
    for (const part of frame.candidates?.[0]?.content?.parts || []) {
      if (part.text) events.push({ type: 'text_delta', text: part.text });
      if (part.functionCall) events.push({ type: 'tool_call_delta', index: 0, name: sanitizeToolId(part.functionCall.name, 'tool'), arguments_delta: JSON.stringify(part.functionCall.args || {}) });
    }
    const finish = nonEmptyFinishReason(frame.candidates?.[0]?.finishReason);
    if (finish) events.push({ type: 'done', finish_reason: finish });
    pushUsage(frame.usageMetadata);
    return events;
  }
  // OpenAI Responses SSE
  if (String(frame.type || '').startsWith('response.')) {
    if (frame.type === 'response.output_text.delta') events.push({ type: 'text_delta', text: frame.delta || '' });
    if (frame.type === 'response.reasoning_summary_text.delta') events.push({ type: 'reasoning_delta', text: frame.delta || '' });
    if (frame.type === 'response.function_call_arguments.delta') events.push({ type: 'tool_call_delta', id: sanitizeToolId(frame.call_id || frame.item_id, 'tool'), index: Number(frame.output_index || 0), arguments_delta: frame.delta || '' });
    if (frame.type === 'response.completed') { pushUsage(frame.response?.usage); const finish = nonEmptyFinishReason(frame.response?.status); if (finish) events.push({ type: 'done', finish_reason: finish }); }
    return events;
  }
  const choice = frame.choices?.[0] || {};
  const delta = choice.delta || {};
  if (delta.content) events.push({ type: 'text_delta', text: delta.content });
  if (delta.reasoning_content || delta.reasoning) events.push({ type: 'reasoning_delta', text: delta.reasoning_content || delta.reasoning });
  for (const call of delta.tool_calls || []) events.push({ type: 'tool_call_delta', id: sanitizeToolId(call.id || `tool_${call.index || 0}`), index: Number(call.index || 0), name: call.function?.name ? sanitizeToolId(call.function.name, 'tool') : null, arguments_delta: call.function?.arguments || '' });
  pushUsage(frame.usage);
  const finish = nonEmptyFinishReason(choice.finish_reason);
  if (finish) events.push({ type: 'done', finish_reason: finish });
  return events;
}

/** 没有非空 finish reason 的工具缓冲一律不可执行，防止半截 JSON 被误触发。 */
export function finalizeToolCalls(deltas, finishReason) {
  const finish = nonEmptyFinishReason(finishReason);
  if (!finish) return { complete: false, reason: 'missing_finish_reason', tool_calls: [] };
  const byIndex = new Map();
  for (const delta of Array.isArray(deltas) ? deltas : []) {
    if (delta?.type !== 'tool_call_delta') continue;
    const index = Number(delta.index || 0);
    const prior = byIndex.get(index) || { id: sanitizeToolId(delta.id || `tool_${index}`), name: 'tool', arguments_json: '' };
    if (delta.id) prior.id = sanitizeToolId(delta.id);
    if (delta.name) prior.name = sanitizeToolId(delta.name, 'tool');
    prior.arguments_json += delta.arguments_delta || '';
    byIndex.set(index, prior);
  }
  const tool_calls = [...byIndex.entries()].sort(([a], [b]) => a - b).map(([, call]) => {
    let args = null;
    try { args = call.arguments_json ? JSON.parse(call.arguments_json) : {}; } catch { args = null; }
    return { ...call, arguments: args, valid_json: args !== null };
  });
  return { complete: true, finish_reason: finish, tool_calls };
}

// ============================================================
// 流式 tool_calls 聚合器 (by opus-4-8 · 2026-09-05)
// 修复：OpenAI Chat delta 必须按 index 拼接，不能覆盖
// ============================================================

const clampInt = (value, fallback, min = 1) => {
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) && n >= min ? n : fallback;
};

export class StreamingToolCallAggregator {
  constructor() {
    this.byIndex = new Map();
    this.order = [];
    this.text = '';
    this.finishReason = null;
  }

  _slot(index) {
    if (!this.byIndex.has(index)) {
      this.byIndex.set(index, { id: null, name: '', argText: '' });
      this.order.push(index);
    }
    return this.byIndex.get(index);
  }

  ingestOpenAIChatChunk(chunk) {
    const choice = chunk?.choices?.[0];
    if (!choice) return;
    const delta = choice.delta || {};
    if (typeof delta.content === 'string') this.text += delta.content;
    if (choice.finish_reason) this.finishReason = choice.finish_reason;
    for (const tc of delta.tool_calls || []) {
      const index = Number.isInteger(tc.index) ? tc.index : this.order.length;
      const slot = this._slot(index);
      if (tc.id) slot.id = tc.id;
      if (tc.function?.name) slot.name = tc.function.name;
      if (typeof tc.function?.arguments === 'string') slot.argText += tc.function.arguments; // 拼接不覆盖
    }
  }

  ingestOpenAIResponsesEvent(evt) {
    const type = evt?.type;
    if (type === 'response.output_text.delta' && typeof evt.delta === 'string') {
      this.text += evt.delta;
    } else if (type === 'response.output_item.added' && evt.item?.type === 'function_call') {
      const index = Number.isInteger(evt.output_index) ? evt.output_index : this.order.length;
      const slot = this._slot(index);
      slot.id = evt.item.call_id || evt.item.id || slot.id;
      slot.name = evt.item.name || slot.name;
    } else if (type === 'response.function_call_arguments.delta') {
      const index = Number.isInteger(evt.output_index) ? evt.output_index : this.order.length - 1;
      const slot = this._slot(index < 0 ? 0 : index);
      if (typeof evt.delta === 'string') slot.argText += evt.delta;
    } else if (type === 'response.completed' || type === 'response.incomplete') {
      this.finishReason = evt.response?.status || this.finishReason;
    }
  }

  ingestAnthropicEvent(evt) {
    const type = evt?.type;
    if (type === 'content_block_start' && evt.content_block?.type === 'tool_use') {
      const slot = this._slot(evt.index);
      slot.id = evt.content_block.id || slot.id;
      slot.name = evt.content_block.name || slot.name;
    } else if (type === 'content_block_delta') {
      const slot = this.byIndex.get(evt.index);
      if (evt.delta?.type === 'input_json_delta' && slot) {
        slot.argText += evt.delta.partial_json || '';
      } else if (evt.delta?.type === 'text_delta') {
        this.text += evt.delta.text || '';
      }
    } else if (type === 'message_delta' && evt.delta?.stop_reason) {
      this.finishReason = evt.delta.stop_reason;
    }
  }

  ingestGeminiChunk(chunk) {
    const cand = chunk?.candidates?.[0];
    if (!cand) return;
    if (cand.finishReason) this.finishReason = cand.finishReason;
    let index = this.order.length;
    for (const part of cand.content?.parts || []) {
      if (typeof part.text === 'string') this.text += part.text;
      if (part.functionCall) {
        const slot = this._slot(index++);
        slot.name = part.functionCall.name || slot.name;
        slot.argText = JSON.stringify(part.functionCall.args || {});
      }
    }
  }

  finalize() {
    const tool_calls = this.order.map((index, i) => {
      const slot = this.byIndex.get(index);
      let args = {};
      let parseError = null;
      const raw = slot.argText.trim();
      if (raw) {
        try { args = JSON.parse(raw); }
        catch (err) { parseError = String(err?.message || err); }
      }
      return {
        id: normalizeToolCallId(slot.id) || sanitizeToolId(slot.id || `call_${i}`),
        name: sanitizeToolId(slot.name, 'tool'),
        arguments: args,
        ...(parseError ? { _raw_arguments: slot.argText, _parse_error: parseError } : {}),
      };
    });
    return { content: this.text || null, tool_calls, finish_reason: nonEmptyFinishReason(this.finishReason) };
  }
}

/** SSE data: 行解析器，跳过注释和 [DONE] */
export function* parseSSELines(buffer) {
  for (const line of String(buffer).split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith(':')) continue;
    if (!trimmed.startsWith('data:')) continue;
    const payload = trimmed.slice(5).trim();
    if (payload === '[DONE]') return;
    try { yield JSON.parse(payload); } catch { /* 跳过不完整分片 */ }
  }
}
