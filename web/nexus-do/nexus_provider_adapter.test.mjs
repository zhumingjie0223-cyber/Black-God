import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ReasoningEcho,
  buildProviderRequest,
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
