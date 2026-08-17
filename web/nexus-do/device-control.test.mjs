import test from 'node:test';
import assert from 'node:assert/strict';
import { ShenshuCore } from './nexus_do.core.mjs';
import { describeCapabilities } from './capabilities.mjs';

function makeCore(overrides = {}) {
  const core = Object.create(ShenshuCore.prototype);
  core.state = { storage: { get: async () => null, put: async () => {} } };
  core.env = {};
  core.getSoul = async () => ({ episodes: [], inner_voice: [] });
  core.saveSoul = async () => {};
  core.consolidateMemory = () => {};
  core.deviceControl = async () => ({ ok: true });
  Object.assign(core, overrides);
  return core;
}

test('device_control 对非主人拒绝且不触发设备调用', async () => {
  const core = makeCore({
    deviceControl: async () => { throw new Error('不应被调用'); },
  });
  const result = await core.invokeCapability('device_control', { action: 'location' }, false);
  assert.deepEqual(result, { action: 'error', data: { reason: 'owner_only', id: 'device_control' } });
});

test('device_control 对主人透传 action 与完整参数', async () => {
  const calls = [];
  const core = makeCore({
    deviceControl: async (action, params) => {
      calls.push({ action, params });
      return { ok: true, action, text: params.text };
    },
  });
  const params = { action: 'clipboard_write', text: '神枢在此' };
  const result = await core.invokeCapability('device_control', params, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].action, 'clipboard_write');
  // 预检会返回安全归一化后的参数副本；验证值完整透传，而不将对象引用身份当成协议契约。
  assert.deepEqual(calls[0].params, params);
  assert.equal(result.action, 'invoke');
  assert.equal(result.data.id, 'device_control');
  assert.deepEqual(result.data.result, { ok: true, action: 'clipboard_write', text: '神枢在此' });
});

test('device_control 已进入私人能力清单', () => {
  assert.ok(describeCapabilities(true).some((cap) => cap.id === 'device_control'));
  assert.ok(!describeCapabilities(false).some((cap) => cap.id === 'device_control'));
});

test('既有自主守望能力仍然保留', () => {
  assert.ok(describeCapabilities(true).some((cap) => cap.id === 'watch'));
});

test('device_control 只注册一次', () => {
  assert.equal(describeCapabilities(true).filter((cap) => cap.id === 'device_control').length, 1);
});
