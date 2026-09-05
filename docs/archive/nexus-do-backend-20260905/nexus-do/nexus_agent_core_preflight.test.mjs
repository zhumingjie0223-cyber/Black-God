import test from 'node:test';
import assert from 'node:assert/strict';
import { AgentStateMachineDO, resolveLeaseTtlMs } from './nexus_agent_core.mjs';

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

// ══════════════════════════════════════════════════════════════
// 租约时长配置（2026-09 补）
// 老实现在模块顶层读 process.env，模块求值发生在 isolate 启动时、拿不到绑定，
// 等于 wrangler 里配了 AGENT_LEASE_TTL_MS 也不生效。改为构造时从 env 绑定解析。
// ══════════════════════════════════════════════════════════════

test('租约时长: 默认 30 秒', () => {
  assert.equal(resolveLeaseTtlMs({}), 30_000);
  assert.equal(resolveLeaseTtlMs(undefined), 30_000);
});

test('租约时长: 读 Workers env 绑定（不是模块顶层的 process.env）', () => {
  assert.equal(resolveLeaseTtlMs({ AGENT_LEASE_TTL_MS: 60_000 }), 60_000);
  assert.equal(resolveLeaseTtlMs({ AGENT_LEASE_TTL_MS: '45000' }), 45_000, 'wrangler vars 传进来是字符串');
});

test('租约时长: 下限 1 秒，挡住 0/负数/非数导致租约一发出就过期', () => {
  for (const bad of [0, -1, -99999, 500, '0', '-5']) {
    assert.equal(resolveLeaseTtlMs({ AGENT_LEASE_TTL_MS: bad }), 1_000, `${bad} 应被钳到下限`);
  }
  for (const bad of ['abc', '', null, {}, NaN, Infinity]) {
    assert.equal(resolveLeaseTtlMs({ AGENT_LEASE_TTL_MS: bad }), 30_000, `${String(bad)} 应退回默认值`);
  }
});

test('租约时长: 实例上生效，派发出的租约到期时间用的是配置值', async () => {
  const agent = new AgentStateMachineDO(makeState(), { AGENT_LEASE_TTL_MS: 5_000 });
  assert.equal(agent.LEASE_TTL_MS, 5_000);
  const before = Date.now();
  await agent.storage.put('queue', [{ id: 'x1', task: 'demo', enqueuedAt: before }]);
  const res = await agent.handleDispatch();
  const body = await res.json();
  assert.equal(body.ok, true);
  const ttl = body.lease.expiry - body.lease.acquiredAt;
  assert.equal(ttl, 5_000, '租约时长必须来自 env 配置，而不是写死的 30s');
});
