import test from 'node:test';
import assert from 'node:assert/strict';
import { ShenshuCore } from './nexus_do.core.mjs';

test('真实 runAgentLoop 对独立只读工具并发执行且按模型源索引回灌', async () => {
  const core = Object.create(ShenshuCore.prototype);
  core.storage = { get: async () => ({}) };
  let brainCalls = 0;
  let active = 0;
  let peak = 0;
  const toolCalls = Array.from({ length: 12 }, (_, index) => ({ tool: 'web_search', arg: `q${index}` }));
  core.gw = { arbitrate: (items) => items, buildWorkspaceBlock: () => '' };
  core.callBrain = async () => {
    brainCalls++;
    return brainCalls === 1 ? { reply: 'tool-plan', model: 'test' } : { reply: 'final-answer', model: 'test' };
  };
  core.parseToolCalls = (reply) => reply === 'tool-plan' ? toolCalls : [];
  core.stripToolMarks = (reply) => reply;
  core.webSearch = async (arg) => {
    active++;
    peak = Math.max(peak, active);
    await new Promise((resolve) => setTimeout(resolve, (11 - Number(arg.slice(1))) % 5));
    active--;
    return `result:${arg}`;
  };
  core.broadcast = () => {};
  core.classifyFailure = () => 'unknown';

  const result = await core.runAgentLoop('sys', 'find', {}, {});
  assert.equal(result.reply, 'final-answer');
  assert.equal(brainCalls, 2);
  assert.equal(result.tool_log.length, 10, '每轮仅允许前十个独立只读工具');
  assert.ok(peak <= 10, `peak=${peak}`);
  assert.deepEqual(result.tool_log.map((record) => record.arg), Array.from({ length: 10 }, (_, i) => `q${i}`));
  assert.deepEqual(result.tool_log.map((record) => record.source_index), Array.from({ length: 10 }, (_, i) => i));
});
