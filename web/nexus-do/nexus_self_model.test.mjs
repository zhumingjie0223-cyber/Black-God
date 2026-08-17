// nexus_self_model.test.mjs
// 运行：node --test nexus_self_model.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PhenomenalSelfModel } from './nexus_self_model.mjs';

// 构造一个最小老soul（故意不含self_model/shu_trajectory，验证兜底）
function makeOldSoul() {
  return {
    心绪: 0.5,
    亲密度: 0.3,
    encounters: 10,
    current_shu_coord: { c: 100, m: 50, s: 20, k: 10, p: 3 },
  };
}

test('failure事件：老soul兜底不崩，failed入库，当前局限与轨迹更新', () => {
  const sm = new PhenomenalSelfModel();
  const soul = makeOldSoul();

  // 老soul没有self_model字段，update不应抛异常
  sm.update(soul, { type: 'failure', content: '部署wrangler配置失败', tool: 'exec', coord: soul.current_shu_coord });

  assert.equal(soul.self_model.能力边界.failed.length, 1);
  assert.equal(soul.self_model.能力边界.failed[0].tool, 'exec');
  assert.ok(soul.self_model.当前局限.includes('部署wrangler配置失败'));
  assert.ok(soul.self_model.自我诊断.length > 0);
  // shu_trajectory 被兜底创建并追加了一条 self_update
  assert.equal(soul.shu_trajectory.length, 1);
  assert.equal(soul.shu_trajectory[0].type, 'self_update');
  assert.equal(soul.shu_trajectory[0].event_type, 'failure');
});

test('success事件：曾失败的能力从failed移到confirmed', () => {
  const sm = new PhenomenalSelfModel();
  const soul = makeOldSoul();

  sm.update(soul, { type: 'failure', content: '写正则', tool: 'regex' });
  assert.equal(soul.self_model.能力边界.failed.length, 1);

  // 同tool的成功事件应把failed里的记录移走并进confirmed
  sm.update(soul, { type: 'success', content: '写正则', tool: 'regex' });
  assert.equal(soul.self_model.能力边界.failed.length, 0);
  assert.ok(soul.self_model.能力边界.confirmed.some((c) => c.content === '写正则'));
});

test('correction检测与更新：红线入库，buildSelfAwareness第一人称且≤300字', () => {
  const sm = new PhenomenalSelfModel();
  const soul = makeOldSoul();

  // detectCorrection
  assert.equal(sm.detectCorrection('不对，你之前搞错了'), true);
  assert.equal(sm.detectCorrection('今天天气不错'), false);
  assert.equal(sm.detectCorrection(''), false);

  // 含"以后不要"的纠错应进红线
  sm.update(soul, { type: 'correction', content: '以后不要解释过程，直接给结果' });
  assert.equal(soul.self_model.对用户的模型.红线.length, 1);

  // 普通纠错进偏好
  sm.update(soul, { type: 'correction', content: '我说的是用中文回复' });
  assert.equal(soul.self_model.对用户的模型.偏好.length, 1);

  const awareness = sm.buildSelfAwareness(soul);
  assert.ok(awareness.length > 0);
  assert.ok(awareness.length <= 300);
  // 透明性：不出现"设定"字样
  assert.ok(!awareness.includes('设定'));
  // 红线内容有体现
  assert.ok(awareness.includes('不要'));
});
