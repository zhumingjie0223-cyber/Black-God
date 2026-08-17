// device-danger-gate.test.mjs
// 覆盖 deviceControl 危险动作二次确认闸门（SAFE / CONFIRM 分级）
import test from 'node:test';
import assert from 'node:assert/strict';
import { ShenshuCore } from './nexus_do.core.mjs';

function makeDevice() {
  const calls = [];
  const spy = async (...args) => {
    calls.push(args);
    return { ok: true, stdout: '{}', stderr: '', exit_code: 0 };
  };
  const dev = Object.create(ShenshuCore.prototype);
  dev.deviceShellExec = spy;
  dev.__calls = calls;
  return dev;
}

test('SAFE 动作 weather 不需要 confirm，直接放行', async () => {
  const dev = makeDevice();
  const res = await dev.deviceControl('weather', {});
  assert.notEqual(res?.need_confirm, true, 'weather 属 SAFE，不该被闸门拦下');
});

test('CONFIRM 动作 clipboard_write 缺 confirm → need_confirm，不触发 shell', async () => {
  const dev = makeDevice();
  const res = await dev.deviceControl('clipboard_write', { text: 'hello' });
  assert.equal(res.ok, false);
  assert.equal(res.need_confirm, true);
  assert.equal(res.action, 'clipboard_write');
  assert.match(res.note, /二次确认/);
  assert.equal(dev.__calls.length, 0, '未确认前绝不能下发命令');
});

test('CONFIRM 动作 clipboard_write 带 confirm:true → 放行执行', async () => {
  const dev = makeDevice();
  const res = await dev.deviceControl('clipboard_write', { text: 'hello', confirm: true });
  assert.notEqual(res?.need_confirm, true, '带 confirm 后不该再被拦');
  assert.ok(dev.__calls.length > 0, '带 confirm 后应调用 shell');
});

test('open_app 普通 URL → SAFE，直接放行', async () => {
  const dev = makeDevice();
  const res = await dev.deviceControl('open_app', { url: 'weixin://' });
  assert.notEqual(res?.need_confirm, true, '普通 App 跳转不应拦截');
});

test('open_app 含支付关键词 → need_confirm', async () => {
  const payUrls = [
    'alipay://platformapi/startapp',
    'weixin://pay/12345',
    'https://example.com/transfer?amt=100',
    'https://Example.com/PAY',
  ];
  for (const url of payUrls) {
    const dev = makeDevice();
    const res = await dev.deviceControl('open_app', { url });
    assert.equal(res.need_confirm, true, `支付类 URL 必须拦截: ${url}`);
    assert.equal(dev.__calls.length, 0, `拦截后不应调 shell: ${url}`);
  }
  // scheme 字段同样生效
  const dev2 = makeDevice();
  const res2 = await dev2.deviceControl('open_app', { scheme: 'alipays://pay' });
  assert.equal(res2.need_confirm, true, 'scheme 字段也要参与判定');
});

test('raw 动作缺 confirm → need_confirm，不触发 shell', async () => {
  const dev = makeDevice();
  const res = await dev.deviceControl('raw', { cmd: 'rm -rf /tmp/x' });
  assert.equal(res.ok, false);
  assert.equal(res.need_confirm, true);
  assert.equal(res.action, 'raw');
  assert.equal(dev.__calls.length, 0, 'raw 未确认绝不下发');
});

test('action 大小写不敏感，闸门照样生效', async () => {
  const dev = makeDevice();
  const res = await dev.deviceControl('RAW', {});
  assert.equal(res.need_confirm, true);
  assert.equal(res.action, 'raw');
});
