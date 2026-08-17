import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AgentRunPhase,
  NexusAgentProtocol,
  allowedTransition,
  redactSecrets,
  riskForCapability,
} from './nexus_agent_protocol.mjs';

const ids = ['a', 'b', 'c', 'd', 'e', 'f'];
const makeProtocol = () => {
  let now = 1_700_000_000_000;
  return {
    protocol: new NexusAgentProtocol({
      clock: () => now,
      randomId: () => ids.shift() || 'z',
      approvalTtlMs: 60_000,
      executionLeaseMs: 60_000,
    }),
    tick: (ms) => { now += ms; },
  };
};

test('高风险 device_control 必须先确认，再领取执行租约', () => {
  const { protocol } = makeProtocol();
  const run = protocol.createPlan({ capability: 'device_control', params: { action: 'notify', text: '神枢在此' } });
  assert.equal(run.risk, 'device');
  assert.equal(run.phase, AgentRunPhase.AWAITING_APPROVAL);
  assert.ok(run.approvalToken);
  assert.ok(run.approval?.tokenHash);
  assert.throws(() => protocol.claim(run), /approval_required/);

  const approved = protocol.approve(run, run.approvalToken).run;
  assert.equal(approved.phase, AgentRunPhase.APPROVED);
  assert.equal(approved.approval.tokenHash, null);
  assert.equal(approved.approvalToken, undefined);
  const claimed = protocol.claim(approved).run;
  assert.equal(claimed.phase, AgentRunPhase.EXECUTING);
  assert.ok(claimed.lease?.token);
});

test('确认令牌错误、过期或消费后均不可重放', () => {
  const { protocol, tick } = makeProtocol();
  const run = protocol.createPlan({ capability: 'exec', params: { command: 'echo safe' } });
  assert.throws(() => protocol.approve(run, 'wrong'), /invalid_approval_token/);
  tick(61_000);
  assert.throws(() => protocol.approve(run, run.approvalToken), /approval_expired/);

  const again = makeProtocol().protocol;
  const run2 = again.createPlan({ capability: 'push', params: { title: 't' } });
  const approved = again.approve(run2, run2.approvalToken).run;
  assert.throws(() => again.approve(approved, 'anything'), /run_not_awaiting_approval/);
});

test('低风险读取能力可以直接执行，但完成后不可回跳', () => {
  const { protocol } = makeProtocol();
  const run = protocol.createPlan({ capability: 'talk', params: { text: '你好' } });
  assert.equal(run.risk, 'read');
  assert.equal(run.phase, AgentRunPhase.PLANNED);
  const claimed = protocol.claim(run).run;
  const done = protocol.complete(claimed, claimed.lease.token, true, { response: '在。' }).run;
  assert.equal(done.phase, AgentRunPhase.SUCCEEDED);
  assert.equal(allowedTransition(done.phase, AgentRunPhase.EXECUTING), false);
  assert.throws(() => protocol.claim(done), /run_not_executable/);
});

test('效果键只随能力、参数、角色和调用键变化，并能区分实际副作用', () => {
  const one = new NexusAgentProtocol({ clock: () => 1, randomId: () => 'same' });
  const two = new NexusAgentProtocol({ clock: () => 1, randomId: () => 'same' });
  const a = one.createPlan({ capability: 'push', params: { title: 'A' }, role: 'system', requestId: 'x' });
  const b = two.createPlan({ capability: 'push', params: { title: 'A' }, role: 'system', requestId: 'x' });
  const c = two.createPlan({ capability: 'push', params: { title: 'B' }, role: 'system', requestId: 'x' });
  assert.equal(a.effectId, b.effectId);
  assert.notEqual(a.effectId, c.effectId);
});

test('审计字段递归隐藏 token、cookie、authorization 和 key', () => {
  const clean = redactSecrets({
    api_key: 'abc',
    nested: { authorization: 'Bearer x', keep: '可读文本' },
    list: [{ cookie: 'sid=1' }, { normal: 3 }],
  });
  assert.equal(clean.api_key, '[REDACTED]');
  assert.equal(clean.nested.authorization, '[REDACTED]');
  assert.equal(clean.nested.keep, '可读文本');
  assert.equal(clean.list[0].cookie, '[REDACTED]');
});

test('风险分级将副作用与读操作分开', () => {
  assert.equal(riskForCapability('talk'), 'read');
  assert.equal(riskForCapability('watch'), 'schedule');
  assert.equal(riskForCapability('tg'), 'communicate');
  assert.equal(riskForCapability('gen_image'), 'create');
  assert.equal(riskForCapability('apple'), 'device');
});
