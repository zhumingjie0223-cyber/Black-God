// device-execute.test.mjs
// parse→execute 贯通测试 for deviceControl
import test from 'node:test';
import assert from 'node:assert/strict';
import { ShenshuCore } from './nexus_do.core.mjs';

// ---- helpers ----------------------------------------------------------------

function makeCore() {
  return Object.create(ShenshuCore.prototype);
}

function makeStub(stdout = '{}', ok = true) {
  const calls = [];
  const fn = async (cmd, shell) => {
    calls.push({ cmd, shell });
    return { ok, stdout, stderr: ok ? '' : 'err', exit_code: ok ? 0 : 1 };
  };
  fn.calls = calls;
  return fn;
}

function makeThrowStub(message) {
  const calls = [];
  const fn = async (cmd, shell) => {
    calls.push({ cmd, shell });
    throw new Error(message);
  };
  fn.calls = calls;
  return fn;
}

// extractAgentActions(text, reply): text=用户原文, reply=模型回复(含⟨工具:device｜…⟩)
function parseActions(core, deviceStr) {
  return core.extractAgentActions('', deviceStr);
}

// ===========================================================================
// A. 正常路径
// ===========================================================================

test('A1: clipboard_write parse→execute 贯通', async () => {
  const core = makeCore();
  const actions = parseActions(core, '⟨工具:device｜clipboard_write text=写入内容⟩');
  assert.equal(actions.length, 1);
  const parsed = actions[0];
  assert.equal(parsed.ok, true);
  assert.equal(parsed.action, 'clipboard_write');
  assert.equal(parsed.params.text, '写入内容');

  core.deviceShellExec = makeStub('OK', true);
  const res = await core.deviceControl(parsed.action, parsed.params);

  assert.equal(res.ok, true);
  assert.equal(res.written, '写入内容');
  assert.equal(core.deviceShellExec.calls.length, 1);
  assert.match(core.deviceShellExec.calls[0].cmd, /apple-clipboard/);
  assert.match(core.deviceShellExec.calls[0].cmd, /写入内容/);
});

test('A2: maps search parse→execute 贯通，query 与 limit 透传', async () => {
  const core = makeCore();
  const actions = parseActions(core, '⟨工具:device｜maps sub=search --query 故宫 limit=3⟩');
  assert.equal(actions.length, 1);
  const parsed = actions[0];
  assert.equal(parsed.ok, true);
  assert.equal(parsed.action, 'maps');
  assert.equal(parsed.params.query, '故宫');
  assert.equal(parsed.params.limit, 3);

  core.deviceShellExec = makeStub('{"places":[{"name":"故宫"}]}', true);
  const res = await core.deviceControl(parsed.action, parsed.params);

  assert.equal(res.ok, true);
  assert.equal(res.action, 'maps');
  assert.equal(res.query, '故宫');
  assert.equal(core.deviceShellExec.calls.length, 1);
  assert.match(core.deviceShellExec.calls[0].cmd, /apple-maps/);
  assert.match(core.deviceShellExec.calls[0].cmd, /故宫/);
});

test('A3: weather 北京 parse→execute，无坐标不加 lat/lon 参数', async () => {
  const core = makeCore();
  const plan = core.parseDeviceActionPlan('weather 北京');
  assert.equal(plan.ok, true);
  assert.ok(
    plan.params.query === '北京' || plan.params.city === '北京',
    `城市丢失: ${JSON.stringify(plan.params)}`,
  );

  core.deviceShellExec = makeStub('{"temp":20}', true);
  const res = await core.deviceControl(plan.action, plan.params);

  assert.equal(res.ok, true);
  assert.equal(res.action, 'weather');
  assert.equal(core.deviceShellExec.calls.length, 1);
  assert.doesNotMatch(core.deviceShellExec.calls[0].cmd, /--lat|--lon/);
});

// ===========================================================================
// B. 降级/错误路径
// ===========================================================================

test('B4: 不支持的 action → parse ok:false，未知动作 execute 不调 shell', async () => {
  const core = makeCore();
  const actions = parseActions(core, '⟨工具:device｜explode⟩');

  assert.ok(actions.length >= 1);
  const errItem = actions.find(a => a.ok === false);
  assert.ok(errItem, '应含 ok:false 错误项');
  assert.match(errItem.error, /不支持/);

  // 没有任何合法 action → hasUsable 为 false → 兜底启发式条件成立
  assert.equal(actions.some(a => a.ok !== false), false);

  // execute 对未知 action 返回失败，不 throw，不调 shell
  core.deviceShellExec = makeStub('{}', true);
  let res;
  await assert.doesNotReject(async () => {
    res = await core.deviceControl('explode', {});
  });
  assert.equal(res.ok, false);
  assert.match(res.error, /未知的 deviceControl 动作/);
  assert.equal(core.deviceShellExec.calls.length, 0);
});

test('B5: 混合合法/非法，合法项 execute 成功，非法项跳过', async () => {
  const core = makeCore();
  const actions = parseActions(core, '⟨工具:device｜weather⟩ ⟨工具:device｜explode⟩');

  assert.equal(actions.length, 2);
  assert.equal(actions[0].ok, true);
  assert.equal(actions[0].action, 'weather');
  assert.equal(actions[1].ok, false);

  core.deviceShellExec = makeStub('{"temp":20}', true);
  const results = [];
  for (const a of actions) {
    if (a.ok === false) continue;
    results.push(await core.deviceControl(a.action, a.params ?? {}));
  }

  assert.equal(results.length, 1);
  assert.equal(results[0].ok, true);
  assert.equal(core.deviceShellExec.calls.length, 1);
});

// ===========================================================================
// C. 执行侧边界
// ===========================================================================

test('C6: clipboard_write 缺 text → 直接失败，不调 shell', async () => {
  const core = makeCore();
  core.deviceShellExec = makeStub('OK', true);

  const res = await core.deviceControl('clipboard_write', {});
  assert.equal(res.ok, false);
  assert.equal(res.error, '缺少 text 参数');
  assert.equal(core.deviceShellExec.calls.length, 0);
});

test('C7: shell 抛"离线"错误 → catch 返回离线消息，不 re-throw', async () => {
  const core = makeCore();
  core.deviceShellExec = makeThrowStub('relay 中继离线，无法连接');

  let res;
  await assert.doesNotReject(async () => {
    res = await core.deviceControl('weather', {});
  });
  assert.equal(res.ok, false);
  assert.equal(res.error, '设备 shell 中继离线');
});
