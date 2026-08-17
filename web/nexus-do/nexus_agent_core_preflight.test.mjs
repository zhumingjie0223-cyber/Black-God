import test from 'node:test';
import assert from 'node:assert/strict';
import { AgentStateMachineDO } from './nexus_agent_core.mjs';

function makeState() {
  const map = new Map();
  return {
    storage: {
      get: async (key) => map.get(key),
      put: async (key, value) => void map.set(key, value),
      delete: async (key) => void map.delete(key),
      list: async () => new Map(),
      getAlarm: async () => null,
      setAlarm: async () => {},
    },
  };
}

async function plan(agent, body) {
  return agent.fetch(new Request('https://agent-ledger/plan', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }));
}

test('Agent DO 在 createPlan 之前执行字段级预检', async () => {
  const agent = new AgentStateMachineDO(makeState(), {});
  const invalidExec = await plan(agent, { capability: 'exec', params: {}, role: 'system', idempotencyKey: 'bad-exec' });
  assert.equal(invalidExec.status, 400);
  assert.equal((await invalidExec.json()).error, 'tool_preflight_failed');

  const invalidDevice = await plan(agent, { capability: 'device_control', params: { action: 'erase_phone' }, role: 'system', idempotencyKey: 'bad-device' });
  assert.equal(invalidDevice.status, 400);

  const accepted = await plan(agent, { capability: 'exec', params: { command: '  echo ok  ' }, role: 'system', idempotencyKey: 'good-exec' });
  assert.equal(accepted.status, 201);
  const body = await accepted.json();
  assert.equal(body.run.capability, 'exec');
  assert.equal(body.run.params.command, 'echo ok');
});
