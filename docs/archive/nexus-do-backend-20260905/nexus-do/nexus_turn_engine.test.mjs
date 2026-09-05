import test from 'node:test';
import assert from 'node:assert/strict';
import {
  NexusTurnEngine,
  appendAgentTurn,
  compactAgentHistory,
  executeToolCallsBounded,
  normalizeToolCalls,
  repairAgentHistory,
} from './nexus_turn_engine.mjs';

test('回合历史会丢弃 partial、孤立结果，并为中断工具调用补齐失败帧', () => {
  const fixed = repairAgentHistory({ messages: [
    { role: 'user', content: '查天气' },
    { role: 'assistant', content: '{半截 JSON', partial: true },
    { role: 'tool', tool_call_id: 'orphan', name: 'web_search', content: '不应保留' },
    { role: 'assistant', content: '', tool_calls: [{ id: 'call:1', name: 'web_search', arguments: { q: '北京天气' } }] },
    { role: 'user', content: '继续' },
  ] });
  assert.equal(fixed.messages.length, 4);
  assert.deepEqual(fixed.messages.map((m) => m.role), ['user', 'assistant', 'tool', 'user']);
  assert.equal(fixed.messages[2].tool_call_id, 'call_1');
  assert.equal(fixed.messages[2].synthetic, true);
  assert.match(fixed.messages[2].content, /missing_tool_result_before_next_message/);
});

test('工具调用 ID 在单个回合内和跨回合 history 中均保持唯一', () => {
  const once = normalizeToolCalls([
    { id: 'same id', name: 'a' },
    { id: 'same id', name: 'b' },
  ], 't');
  assert.deepEqual(once.map((c) => c.id), ['same_id', 'same_id_2']);

  const fixed = repairAgentHistory({ messages: [
    { role: 'assistant', content: '', tool_calls: [{ id: 'same', name: 'a' }] },
    { role: 'tool', tool_call_id: 'same', name: 'a', content: '{}' },
    { role: 'assistant', content: '', tool_calls: [{ id: 'same', name: 'b' }] },
    { role: 'tool', tool_call_id: 'same_2', name: 'b', content: '{}' },
  ] });
  const ids = fixed.messages.filter((m) => m.role === 'assistant').flatMap((m) => m.tool_calls.map((c) => c.id));
  assert.deepEqual(ids, ['same', 'same_2']);
});

test('UI stream 与规范 Agent history 分离：可展示回答不会被历史修复覆盖', () => {
  const uiMessage = { ts: 1, text: '执行检查', reply: '已完成', model: 'nexus' };
  const history = appendAgentTurn(null, {
    turnId: 'turn-1',
    userText: uiMessage.text,
    assistantText: uiMessage.reply,
    toolLog: [{ id: 'sh', tool: 'exec', arg: 'echo ok', ok: true, latencyMs: 12, output: 'ok' }],
  });
  assert.equal(uiMessage.reply, '已完成');
  assert.equal(history.messages[0].role, 'user');
  assert.equal(history.messages[1].role, 'assistant');
  assert.equal(history.messages[2].role, 'tool');
  assert.equal(history.messages[3].role, 'assistant');
  assert.equal(history.messages[3].content, uiMessage.reply);
  assert.equal(history.messages[2].tool_call_id, history.messages[1].tool_calls[0].id);
  assert.notEqual(history.messages[2], uiMessage);
});

test('消息锚点压缩不拆分工具请求/结果，且记录最后被压缩的 message_id', () => {
  const messages = [
    ...Array.from({ length: 12 }, (_, index) => ({ role: 'user', content: `old-${index}` })),
    { role: 'assistant', content: '', tool_calls: [{ id: 'call-x', name: 'search', arguments: { q: 'x' } }] },
    { role: 'tool', tool_call_id: 'call-x', name: 'search', content: '{"ok":true}' },
    ...Array.from({ length: 18 }, (_, index) => ({ role: 'assistant', content: `new-${index}` })),
  ];
  const compacted = compactAgentHistory({ messages }, { maxMessages: 20 });
  assert.equal(compacted.changed, true);
  assert.equal(compacted.marker.last_compacted_message_id, 'legacy_11');
  const callIndex = compacted.history.messages.findIndex((message) => message.role === 'assistant' && message.tool_calls?.[0]?.id === 'call-x');
  assert.ok(callIndex >= 0);
  assert.equal(compacted.history.messages[callIndex + 1].role, 'tool');
  assert.equal(compacted.history.messages[callIndex + 1].tool_call_id, 'call-x');
  assert.ok(compacted.history.messages[0].content.includes('锚点 legacy_11'));
});

test('工具批处理最多十路并发，完成顺序不会改变 source_index 回灌顺序', async () => {
  let active = 0;
  let peak = 0;
  const calls = Array.from({ length: 25 }, (_, source_index) => ({ id: `c-${source_index}`, tool: 'check', source_index }));
  const results = await executeToolCallsBounded(calls, async ({ call }) => {
    active++;
    peak = Math.max(peak, active);
    await new Promise((resolve) => setTimeout(resolve, (25 - call.source_index) % 7));
    active--;
    return { ok: true, value: call.source_index };
  }, { concurrency: 99 });
  assert.ok(peak <= 10, `peak=${peak}`);
  assert.deepEqual(results.map((r) => r.source_index), Array.from({ length: 25 }, (_, i) => i));
  assert.ok(results.every((r) => r.ok));
});

test('取消信号会拒绝尚未开始的工具，已启动工具仍返回自身真实结果', async () => {
  const controller = new AbortController();
  let started = 0;
  const calls = Array.from({ length: 5 }, (_, i) => ({ id: `c${i}`, tool: 'slow', source_index: i }));
  const promise = NexusTurnEngine.execute(calls, async () => {
    started++;
    if (started === 1) controller.abort();
    await new Promise((resolve) => setTimeout(resolve, 2));
    return { ok: true };
  }, { concurrency: 1, signal: controller.signal });
  const result = await promise;
  assert.equal(result[0].ok, true);
  assert.equal(result.slice(1).filter((x) => x.cancelled).length, 4);
});
