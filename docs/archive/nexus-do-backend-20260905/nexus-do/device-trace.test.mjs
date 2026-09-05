// device-trace.test.mjs
// 覆盖 deviceControl traceDevice 埋点 + classifyFailure 方法
import test from 'node:test';
import assert from 'node:assert/strict';
import { ShenshuCore } from './nexus_do.core.mjs';

function makeDevice() {
  const events = [];
  const dev = Object.create(ShenshuCore.prototype);
  dev.broadcast = (ev) => { events.push(ev); };
  dev.deviceShellExec = async () => ({ ok: true, stdout: '{}', stderr: '', exit_code: 0 });
  dev.__events = events;
  return dev;
}

function getTrace(dev) {
  return dev.__events.find(e => e.type === 'device_trace');
}

// ----------------------------------------------------------------

test('1. 成功动作 broadcast device_trace ok:true', async () => {
  const dev = makeDevice();
  const res = await dev.deviceControl('weather', {});
  assert.ok(res.ok !== false, 'weather 应成功');
  const ev = getTrace(dev);
  assert.ok(ev, '应发出 device_trace');
  assert.equal(ev.ok, true);
  assert.equal(ev.failureType, '');
  assert.equal(ev.action, 'weather');
  assert.equal(ev.tool, 'device_control');
  assert.equal(typeof ev.latencyMs, 'number');
  assert.ok(ev.latencyMs >= 0);
  assert.equal(typeof ev.ts, 'number');
});

test('2. need_confirm → failureType=need_confirm', async () => {
  const dev = makeDevice();
  const res = await dev.deviceControl('clipboard_write', { text: 'hi' }); // 缺 confirm
  assert.equal(res.ok, false);
  assert.equal(res.need_confirm, true);
  const ev = getTrace(dev);
  assert.ok(ev, '应发出 device_trace');
  assert.equal(ev.ok, false);
  assert.equal(ev.failureType, 'need_confirm');
});

test('3. param_missing → failureType=param_missing', async () => {
  const dev = makeDevice();
  // clipboard_write 带 confirm 但缺 text
  const res = await dev.deviceControl('clipboard_write', { confirm: true });
  assert.equal(res.ok, false);
  const ev = getTrace(dev);
  assert.ok(ev, '应发出 device_trace');
  assert.equal(ev.ok, false);
  assert.equal(ev.failureType, 'param_missing');
});

test('4. shell 离线 → failureType=offline', async () => {
  const dev = makeDevice();
  dev.deviceShellExec = async () => { const e = new Error('中继离线'); e.__offline = true; throw e; };
  const res = await dev.deviceControl('weather', {});
  assert.equal(res.ok, false);
  const ev = getTrace(dev);
  assert.ok(ev, '应发出 device_trace');
  assert.equal(ev.failureType, 'offline');
  assert.equal(ev.ok, false);
});

test('5. planId/stepIndex 从 params.__planId/__stepIndex 透传', async () => {
  const dev = makeDevice();
  await dev.deviceControl('weather', { __planId: 'p_test_1234', __stepIndex: 7 });
  const ev = getTrace(dev);
  assert.equal(ev.planId, 'p_test_1234');
  assert.equal(ev.stepIndex, 7);
});

test('5b. 缺省时 planId="" stepIndex=-1', async () => {
  const dev = makeDevice();
  await dev.deviceControl('weather', {});
  const ev = getTrace(dev);
  assert.equal(ev.planId, '');
  assert.equal(ev.stepIndex, -1);
});

test('6. classifyFailure 枚举分类正确', () => {
  const dev = Object.create(ShenshuCore.prototype);
  assert.equal(dev.classifyFailure('设备中继离线'), 'offline');
  assert.equal(dev.classifyFailure('need_confirm: true'), 'need_confirm');
  assert.equal(dev.classifyFailure('缺少 text 参数'), 'param_missing');
  assert.equal(dev.classifyFailure('权限被拒'), 'permission');
  assert.equal(dev.classifyFailure('timeout exceeded'), 'timeout');
  assert.equal(dev.classifyFailure('not found'), 'not_found');
  assert.equal(dev.classifyFailure('something else'), 'unknown');
});
