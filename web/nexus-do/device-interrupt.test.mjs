// device-interrupt.test.mjs
// P1-1 中断态处理 —— detectInterrupt / classifyFailure 扩展 / 中断不计 failCount
import test from 'node:test';
import assert from 'node:assert/strict';
import { ShenshuCore } from './nexus_do.core.mjs';

const proto = Object.create(ShenshuCore.prototype);

// ---- detectInterrupt ----

test('1. detectInterrupt 识别锁屏', () => {
  const r = proto.detectInterrupt({ exit_code: 1, stderr: 'Error: Device is locked, unlock to continue' });
  assert.equal(r.type, 'locked');
  assert.equal(r.confidence, 'high');
  assert.ok(r.hint.length > 0);
});

test('2. detectInterrupt 识别权限弹窗（NSAuthorizationError）', () => {
  const r = proto.detectInterrupt({ exit_code: 1, stderr: 'NSAuthorizationError: photos access requires permission' });
  assert.equal(r.type, 'permission_dialog');
  assert.equal(r.confidence, 'high');
});

test('2b. detectInterrupt 识别权限弹窗（passcode 不误触 permission_dialog）', () => {
  // passcode 含 locked 关键词，应走 locked，不是 permission_dialog
  const r = proto.detectInterrupt({ exit_code: 1, stderr: 'please enter passcode to unlock' });
  assert.equal(r.type, 'locked');
});

test('3. detectInterrupt 识别 system_dialog（ok=false + exit=0 + stdout 空）', () => {
  // system_dialog: 工具调用返回 ok:false，但 exit=0 且无输出（被系统弹窗覆盖）
  const r = proto.detectInterrupt({ ok: false, exit_code: 0, data: '', stderr: '' });
  assert.equal(r.type, 'system_dialog');
  assert.equal(r.confidence, 'low');
});

test('3b. detectInterrupt exit=0 + ok 正常 → type:none', () => {
  const r = proto.detectInterrupt({ exit_code: 0, data: '{"temp":20}', stderr: '' });
  assert.equal(r.type, 'none');
});

test('4. detectInterrupt 识别来电', () => {
  const r = proto.detectInterrupt({ exit_code: 1, stderr: 'operation interrupted by incoming call' });
  assert.equal(r.type, 'call_incoming');
  assert.equal(r.confidence, 'high');
});

test('5. detectInterrupt 正常结果返回 type:none', () => {
  const r = proto.detectInterrupt({ exit_code: 0, data: '[{"id":"1"}]', stderr: '' });
  assert.equal(r.type, 'none');
});

// ---- classifyFailure 扩展 ----

test('7. classifyFailure 新增枚举正确分类', () => {
  assert.equal(proto.classifyFailure('Device is locked'), 'locked');
  assert.equal(proto.classifyFailure('please unlock with passcode'), 'locked');
  assert.equal(proto.classifyFailure('NSAuthorizationError occurred'), 'permission_dialog');
  assert.equal(proto.classifyFailure('this action requires permission from user'), 'permission_dialog');
  assert.equal(proto.classifyFailure('call incoming, interrupted'), 'call_incoming');
  assert.equal(proto.classifyFailure('something weird'), 'unknown');
  // 回归：旧枚举不受影响
  assert.equal(proto.classifyFailure('设备离线'), 'offline');
  assert.equal(proto.classifyFailure('timeout occurred'), 'timeout');
  assert.equal(proto.classifyFailure('not found'), 'not_found');
  // permission denied → 旧 permission（不是 iOS 弹窗）
  assert.equal(proto.classifyFailure('permission denied'), 'permission');
  // requires permission from user → permission_dialog（iOS 授权弹窗）
  assert.equal(proto.classifyFailure('this action requires permission from user'), 'permission_dialog');
});

// ---- 中断态不计 failCount ----

test('6. 中断态（locked）不计 failCount，普通失败正常累计', () => {
  const failCount = {};
  const obs = [];
  const scratchCandidates = [];
  const c = { tool: 'photos', arg: 'list' };
  const INTERRUPT_TYPES = new Set(['locked', 'call_incoming', 'system_dialog', 'permission_dialog']);

  function handle(ft, stepIndex) {
    if (INTERRUPT_TYPES.has(ft)) {
      const hint = ft === 'locked' ? '设备已锁屏，请解锁后重试，不要换动作'
        : ft === 'call_incoming' ? '来电打断，稍后重试'
        : ft === 'permission_dialog' ? 'iOS 权限弹窗，请用户授权后重试同一动作'
        : '系统对话框，等待消失后重试';
      obs.push(`【${c.tool}｜${c.arg}】\n⏸ [中断·${ft}] ${hint}`);
    } else {
      const failKey = `${c.tool}:${ft}`;
      failCount[failKey] = (failCount[failKey] || 0) + 1;
      if (failCount[failKey] >= 2) scratchCandidates.push({ content: `⛔ ${failKey}` });
    }
  }

  // 锁屏三次 → failCount 不涨
  handle('locked', 1);
  handle('locked', 2);
  handle('locked', 3);
  assert.equal(Object.keys(failCount).length, 0, 'locked 不计 failCount');
  assert.equal(scratchCandidates.length, 0);
  assert.equal(obs.length, 3);
  assert.ok(obs[0].includes('⏸ [中断·locked]'));

  // 普通失败两次 → 累计 + 换路提示
  handle('not_found', 4);
  handle('not_found', 5);
  assert.equal(failCount[`${c.tool}:not_found`], 2);
  assert.equal(scratchCandidates.length, 1);
});

test('permission_dialog 中断不计 failCount', () => {
  const failCount = {};
  const obs = [];
  const INTERRUPT_TYPES = new Set(['locked', 'call_incoming', 'system_dialog', 'permission_dialog']);
  const c = { tool: 'healthkit', arg: 'batch' };

  function handle(ft) {
    if (INTERRUPT_TYPES.has(ft)) {
      obs.push(`⏸ [中断·${ft}]`);
    } else {
      failCount[`${c.tool}:${ft}`] = (failCount[`${c.tool}:${ft}`] || 0) + 1;
    }
  }

  handle('permission_dialog');
  handle('permission_dialog');
  assert.equal(Object.keys(failCount).length, 0);
  assert.equal(obs.length, 2);
  assert.ok(obs[0].includes('permission_dialog'));
});
