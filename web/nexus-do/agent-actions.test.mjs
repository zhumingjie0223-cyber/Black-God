import test from 'node:test';
import assert from 'node:assert/strict';
import { ShenshuCore } from './nexus_do.core.mjs';

const core = Object.create(ShenshuCore.prototype);
// makeAgent: 提供 this 上下文等价的实例（供新 case 用）
const makeAgent = () => Object.create(ShenshuCore.prototype);

test('设备标记解析为统一 device_control 计划', () => {
  const result = core.extractAgentActions('', '⟨工具:device｜weather⟩');
  assert.equal(result.length, 1);
  assert.equal(result[0].ok, true);
  assert.equal(result[0].type, 'device_control');
  assert.equal(result[0].capability, 'device_control');
  assert.equal(result[0].action, 'weather');
  assert.deepEqual(result[0].params, {});
});

test('设备动作参数标准化与别名映射', () => {
  const result = core.parseDeviceActionPlan('clipboard-write text=神枢在此');
  assert.equal(result.ok, true);
  assert.equal(result.capability, 'device_control');
  assert.equal(result.action, 'clipboard_write');
  assert.deepEqual(result.params, { text: '神枢在此' });
});

test('maps sub/query 语法转成统一参数', () => {
  const result = core.parseDeviceActionPlan('maps sub=search --query 咖啡馆 limit=3');
  assert.equal(result.action, 'maps');
  assert.equal(result.params.query, '咖啡馆');
  assert.equal(result.params.limit, 3);
});

test('不支持的设备动作只返回计划错误，不执行', () => {
  const result = core.extractAgentActions('', '⟨工具:device｜delete_all⟩');
  assert.equal(result.length, 1);
  assert.equal(result[0].type, 'device_control');
  assert.equal(result[0].ok, false);
  assert.match(result[0].error, /不支持/);
});

test('设备动作与 URL 动作可以同时返回', () => {
  const result = core.extractAgentActions('', '⟨工具:device｜location⟩ https://maps.apple.com/?q=故宫');
  assert.equal(result.length, 2);
  assert.equal(result[0].capability, 'device_control');
  assert.equal(result[1].type, 'open_url');
});

test('成功计划必须带 ok:true（下游 filter 依赖）', () => {
  const agent = makeAgent();
  const result = agent.parseDeviceActionPlan('notify text=会议开始');
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.action, 'notify');
  assert.strictEqual(result.capability, 'device_control');
  assert.strictEqual(result.params.text, '会议开始');
});

test('device 标记内含 URL 不产生 open_url 重复动作', () => {
  const agent = makeAgent();
  const actions = agent.extractAgentActions('打开网站', '⟨工具:device｜open_app url=https://x.com⟩');
  assert.strictEqual(actions.length, 1);
  assert.strictEqual(actions[0].type, 'device_control');
  assert.strictEqual(actions[0].action, 'open_app');
  assert.strictEqual(actions[0].params.url, 'https://x.com');
  assert.ok(!actions.some((a) => a.type === 'open_url'));
});

test('weather 北京 不丢城市', () => {
  const agent = makeAgent();
  const result = agent.parseDeviceActionPlan('weather 北京');
  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.action, 'weather');
  assert.ok(
    result.params.query === '北京' || result.params.city === '北京',
    `城市丢失: ${JSON.stringify(result.params)}`,
  );
});
