// node --test nexus_active_inference.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ActiveInferenceEngine } from './nexus_active_inference.mjs';

// ---- 用例1：instanceMode 下 before 不调 callBrain，直接空预期（铁律）------
test('before: instanceMode 跳过大脑调用，返回空 expected', async () => {
  let brainCalled = 0;
  const engine = new ActiveInferenceEngine(async () => {
    brainCalled++;
    return { reply: 'should not be called' };
  });

  const soul = { world_model: { assumptions: [] } };
  const res = await engine.before('ls -la', soul, { instanceMode: true });

  assert.deepEqual(res, { expected: '' });
  assert.equal(brainCalled, 0, 'instanceMode 下不允许调 callBrain');

  // 顺带验证：非 instanceMode 下会调，且截断到 200 字
  const engine2 = new ActiveInferenceEngine(async () => ({ reply: 'x'.repeat(500) }));
  const res2 = await engine2.before('ls', soul, {});
  assert.equal(res2.expected.length, 200);
});

// ---- 用例2：after 的 delta 与策略分流 --------------------------------------
test('after: 成功匹配→continue，失败严重错配→update_world，一般失败→fix_cmd', async () => {
  // 不给 callBrainFn：update_world 分支不会做诊断调用，纯测策略
  const engine = new ActiveInferenceEngine(null);
  const soul = {};

  // 成功且预期高度重合 → delta 低 → continue
  const r1 = await engine.after('cat version.txt', { ok: true, stdout: 'version 2.1.0 stable release', stderr: '', code: 0 }, 'version stable release', soul);
  assert.equal(r1.strategy, 'continue');
  assert.ok(r1.delta < 0.3, `成功匹配时 delta 应低，实际 ${r1.delta}`);

  // 失败且预期完全错配 → delta ≥ 0.75 → update_world
  const r2 = await engine.after('docker ps', { ok: false, stdout: '', stderr: 'docker: command not found', code: 127 }, '列出运行中容器 CONTAINER ID IMAGE STATUS', soul);
  assert.equal(r2.strategy, 'update_world');
  assert.ok(r2.delta >= 0.75, `严重错配时 delta 应≥0.75，实际 ${r2.delta}`);

  // 一般失败：无预期，delta 中等 → fix_cmd
  const r3 = await engine.after('ls /tmp/x', { ok: false, stdout: '', stderr: 'No such file', code: 2 }, '', soul);
  assert.equal(r3.strategy, 'fix_cmd');
  assert.ok(r3.delta > 0 && r3.delta < 0.75, `一般失败 delta 应在中段，实际 ${r3.delta}`);
});

// ---- 用例3：世界模型更新 + 推理日志兜底与裁剪 ----------------------------
test('updateWorldModel/logInference: 老soul兜底、置信度翻转、日志上限50', () => {
  const engine = new ActiveInferenceEngine(null);
  const soul = { 心绪: 0.5 };

  engine.updateWorldModel(soul, { wrongAssumption: '', newAssumption: '该机器有 docker' });
  engine.updateWorldModel(soul, { wrongAssumption: '该机器有 docker', newAssumption: '该机器没有 docker，只有 podman', shu_word: '容器' });

  const old = soul.world_model.assumptions.find(a => a.text === '该机器有 docker');
  const fresh = soul.world_model.assumptions.find(a => a.text === '该机器没有 docker，只有 podman');
  assert.equal(old.confidence, 0.1);
  assert.equal(fresh.confidence, 0.8);
  assert.equal(fresh.shu_word, '容器');

  for (let i = 0; i < 60; i++) {
    engine.logInference(soul, { cmd: `cmd-${i}`, expected: 'e', actual: 'a', delta: i === 59 ? 1.5 : 0.5 });
  }
  assert.equal(soul.inference_log.length, 50);
  assert.equal(soul.inference_log[49].delta, 1);
});
