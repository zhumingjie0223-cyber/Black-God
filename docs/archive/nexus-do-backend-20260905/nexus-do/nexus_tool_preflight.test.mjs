import test from 'node:test';
import assert from 'node:assert/strict';
import { preflightToolCall } from './nexus_tool_preflight.mjs';

test('未知能力与缺失必填字段在计划前被拒绝', () => {
  assert.equal(preflightToolCall('unknown_tool', {}).ok, false);
  const exec = preflightToolCall('exec', {});
  assert.equal(exec.ok, false);
  assert.ok(exec.errors.some((error) => error.field === 'command'));
});

test('设备控制只接受登记动作与健康枚举，并提示副作用确认', () => {
  const invalid = preflightToolCall('device_control', { action: 'erase_phone' });
  assert.equal(invalid.ok, false);
  const health = preflightToolCall('device_control', { action: 'health', types: 'steps,bad_type' });
  assert.equal(health.ok, false);
  const write = preflightToolCall('device_control', { action: 'clipboard_write', text: 'x' });
  assert.equal(write.ok, true);
  assert.ok(write.warnings.some((warning) => warning.code === 'owner_confirmation_required'));
});

test('文件操作阻止路径穿越，且 file_edit 允许空 new_string 作为删除', () => {
  const badPath = preflightToolCall('file_edit', { path: '../secret', old_string: 'x', new_string: '' });
  assert.equal(badPath.ok, false);
  const remove = preflightToolCall('file_edit', { path: 'workspace/a.txt', old_string: 'remove-me', new_string: '' });
  assert.equal(remove.ok, true);
  assert.equal(remove.normalized.new_string, '');
  const absent = preflightToolCall('file_edit', { path: 'workspace/a.txt', old_string: 'x' });
  assert.equal(absent.ok, false);
  assert.ok(absent.errors.some((error) => error.field === 'new_string'));
});

test('预检保持输入归一化而不把审批 warning 错当为字段错误', () => {
  const push = preflightToolCall('push', { title: '通知', body: '', url: '/' });
  assert.equal(push.ok, true);
  assert.equal(push.normalized.title, '通知');
  const read = preflightToolCall('file_read', { path: '/workspace/a.txt' });
  assert.equal(read.ok, true);
});
