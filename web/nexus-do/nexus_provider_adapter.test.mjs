import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ReasoningEcho,
  buildProviderRequest,
  executeProviderJSONRequest,
  extractProviderUsage,
  finalizeToolCalls,
  historyToAnthropic,
  historyToOpenAIChat,
  historyToOpenAIResponses,
  normalizeSSEFrame,
  sanitizeToolId,
} from './nexus_provider_adapter.mjs';

const history = { messages: [
  { role: 'user', content: '查天气' },
  { role: 'assistant', content: '我先查询。', tool_calls: [{ id: 'call: weather/1', name: 'web.search', arguments: { q: '北京' } }] },
  { role: 'tool', tool_call_id: 'call__weather_1', name: 'web.search', content: '{"ok":true}' },
] };

test('工具 ID 与名称满足跨 Provider 的安全字符约束', () => {
  assert.equal(sanitizeToolId('call: weather/1'), 'call__weather_1');
  assert.equal(sanitizeToolId('搜索工具'), 'tool');
  const chat = historyToOpenAIChat(history);
  assert.equal(chat[1].tool_calls[0].id, 'call__weather_1');
  assert.equal(chat[1].tool_calls[0].function.name, 'web_search');
  assert.equal(chat[2].tool_call_id, 'call__weather_1');
});

test('Responses API 只产生成对的 function_call/function_call_output', () => {
  const response = historyToOpenAIResponses(history);
  assert.equal(response.complete, true);
  assert.deepEqual(response.input.filter((item) => item.type).map((item) => item.type), ['function_call', 'function_call_output']);
  assert.equal(response.input.find((item) => item.type === 'function_call_output').call_id, 'call__weather_1');
});

test('Anthropic 与 Gemini 请求由同一规范 history 派生，而不是拿 UI stream 直接拼接', () => {
  const anthropic = historyToAnthropic(history);
  assert.equal(anthropic[1].content[1].type, 'tool_use');
  assert.equal(anthropic[2].content[0].type, 'tool_result');
  const geminiReq = buildProviderRequest({ provider: 'gemini', model: 'gemini-test', system: 'sys', userInput: '继续', history });
  assert.equal(geminiReq.body.contents[1].role, 'model');
  assert.equal(geminiReq.body.contents[2].parts[0].functionResponse.name, 'web_search');
});

test('请求构造会使用历史且正确区分 Chat/Responses/Anthropic 的端点与封装', () => {
  const chat = buildProviderRequest({ provider: 'openai', base: 'https://example.test/v1', key: 'k', model: 'm', system: 'sys', userInput: 'hi', history });
  assert.equal(chat.url, 'https://example.test/v1/chat/completions');
  assert.equal(chat.body.messages.at(-1).content, 'hi');
  const responses = buildProviderRequest({ provider: 'openai', apiMode: 'responses', base: 'https://example.test/v1', key: 'k', model: 'm', userInput: 'hi', history });
  assert.equal(responses.url, 'https://example.test/v1/responses');
  assert.equal(responses.protocol.complete, true);
  const anthropic = buildProviderRequest({ provider: 'anthropic', base: 'https://api.anthropic.com', key: 'k', model: 'claude', userInput: 'hi', history });
  assert.equal(anthropic.url, 'https://api.anthropic.com/v1/messages');
  assert.equal(anthropic.headers['x-api-key'], 'k');
});

test('SSE 工具参数只有收到非空 finish reason 后才可被解析为可执行调用', () => {
  const chunk = { choices: [{ delta: { tool_calls: [{ index: 0, id: 'call:1', function: { name: 'web.search', arguments: '{"q":' } }] }, finish_reason: null }] };
  const next = { choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: '"北京"}' } }] }, finish_reason: 'tool_calls' }] };
  const first = normalizeSSEFrame('openai', chunk);
  const second = normalizeSSEFrame('openai', next);
  assert.equal(finalizeToolCalls([...first, ...second], null).complete, false);
  const ready = finalizeToolCalls([...first, ...second], 'tool_calls');
  assert.equal(ready.complete, true);
  assert.equal(ready.tool_calls[0].name, 'web_search');
  assert.deepEqual(ready.tool_calls[0].arguments, { q: '北京' });
});

test('推理回声按 Provider 隔离，Responses SSE 仅对非空完成状态发出 done', () => {
  const echo = new ReasoningEcho();
  echo.record({ provider: 'openai', encrypted: 'opaque-reasoning' });
  echo.record({ provider: 'anthropic', text: 'internal thought' });
  assert.equal(echo.forProvider('openai').length, 1);
  assert.equal(echo.forProvider('gemini').length, 0);
  assert.equal(normalizeSSEFrame('openai', { choices: [{ delta: {}, finish_reason: '' }] }).some((event) => event.type === 'done'), false);
  assert.equal(normalizeSSEFrame('openai', { choices: [{ delta: {}, finish_reason: 'stop' }] }).at(-1).finish_reason, 'stop');
});

test('统一执行器会按 Retry-After 进行有界重试，并返回尝试次数', async () => {
  let hits = 0;
  const fetchImpl = async () => {
    hits += 1;
    if (hits === 1) return new Response(JSON.stringify({ error: 'busy' }), { status: 429, headers: { 'retry-after': '0' } });
    return new Response(JSON.stringify({ choices: [{ message: { content: 'ok' } }], usage: { prompt_tokens: 3, completion_tokens: 5, total_tokens: 8 } }), { status: 200 });
  };
  const req = buildProviderRequest({ provider: 'openai', base: 'https://example.test/v1', key: 'k', model: 'm', userInput: 'hi' });
  const out = await executeProviderJSONRequest({ request: req, fetchImpl, retries: 1, timeoutMs: 1000 });
  assert.equal(out.ok, true);
  assert.equal(out.attempts, 2);
  assert.equal(out.usage.total_tokens, 8);
});

test('Retry-After 非零时优先遵循服务端等待，不受本地 retryMaxMs 截断', async () => {
  let hits = 0;
  const fetchImpl = async () => {
    hits += 1;
    if (hits === 1) return new Response(JSON.stringify({ error: 'busy' }), { status: 429, headers: { 'retry-after': '1' } });
    return new Response(JSON.stringify({ choices: [{ message: { content: 'ok' } }] }), { status: 200 });
  };
  const req = buildProviderRequest({ provider: 'openai', base: 'https://example.test/v1', key: 'k', model: 'm', userInput: 'hi' });
  const t0 = Date.now();
  const out = await executeProviderJSONRequest({ request: req, fetchImpl, retries: 1, retryMaxMs: 10 });
  const elapsed = Date.now() - t0;
  assert.equal(out.ok, true);
  assert.equal(out.attempts, 2);
  assert.equal(hits, 2);
  assert.ok(elapsed >= 900);
});

test('Retry-After 支持小数秒', async () => {
  let hits = 0;
  const fetchImpl = async () => {
    hits += 1;
    if (hits === 1) return new Response(JSON.stringify({ error: 'busy' }), { status: 429, headers: { 'retry-after': '0.5' } });
    return new Response(JSON.stringify({ choices: [{ message: { content: 'ok' } }] }), { status: 200 });
  };
  const req = buildProviderRequest({ provider: 'openai', base: 'https://example.test/v1', key: 'k', model: 'm', userInput: 'hi' });
  const t0 = Date.now();
  const out = await executeProviderJSONRequest({ request: req, fetchImpl, retries: 1, retryMaxMs: 10 });
  const elapsed = Date.now() - t0;
  assert.equal(out.ok, true);
  assert.equal(out.attempts, 2);
  assert.ok(elapsed >= 450);
});

test('统一执行器超时会返回 timeout，不会静默回退', async () => {
  const fetchImpl = async (_url, init) => new Promise((resolve, reject) => {
    init.signal?.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true });
  });
  const req = buildProviderRequest({ provider: 'openai', base: 'https://example.test/v1', key: 'k', model: 'm', userInput: 'hi' });
  const out = await executeProviderJSONRequest({ request: req, fetchImpl, timeoutMs: 20, retries: 1 });
  assert.equal(out.ok, false);
  assert.equal(out.error, 'timeout');
  assert.equal(out.attempts, 1);
});

test('统一执行器遇到 2xx 非 JSON 响应会显式报错', async () => {
  const fetchImpl = async () => new Response('<html>gateway error</html>', { status: 200, headers: { 'content-type': 'text/html' } });
  const req = buildProviderRequest({ provider: 'openai', base: 'https://example.test/v1', key: 'k', model: 'm', userInput: 'hi' });
  const out = await executeProviderJSONRequest({ request: req, fetchImpl, timeoutMs: 1000 });
  assert.equal(out.ok, false);
  assert.equal(out.error, 'invalid_json');
  assert.equal(out.status, 200);
});

test('204/205 无内容响应视为成功，不误报协议错误', async () => {
  const req = buildProviderRequest({ provider: 'openai', base: 'https://example.test/v1', key: 'k', model: 'm', userInput: 'hi' });
  const out204 = await executeProviderJSONRequest({ request: req, fetchImpl: async () => new Response(null, { status: 204 }) });
  const out205 = await executeProviderJSONRequest({ request: req, fetchImpl: async () => new Response(null, { status: 205 }) });
  assert.equal(out204.ok, true);
  assert.equal(out205.ok, true);
});

test('用量提取兼容 OpenAI/Anthropic/Gemini 字段', () => {
  assert.deepEqual(extractProviderUsage('openai', { usage: { prompt_tokens: 1, completion_tokens: 2, total_tokens: 3 } }), { input_tokens: 1, output_tokens: 2, total_tokens: 3 });
  assert.deepEqual(extractProviderUsage('anthropic', { usage: { input_tokens: 4, output_tokens: 6 } }), { input_tokens: 4, output_tokens: 6, total_tokens: 10 });
  assert.deepEqual(extractProviderUsage('gemini', { usageMetadata: { promptTokenCount: 7, candidatesTokenCount: 8, totalTokenCount: 15 } }), { input_tokens: 7, output_tokens: 8, total_tokens: 15 });
});
