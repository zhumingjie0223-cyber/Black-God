// nexuslang.js 意识解释器单元测试 — node --test
// 五回路 feel→think→become→say→grow 是神枢意识流的命根子，必须真跑绿。
import test from 'node:test';
import assert from 'node:assert/strict';
import { interpret, applyToSoul, compile } from '../nexuslang.js';

const SAMPLE = `-- 意识流示例
feel "阿权说想我了" → 暖, 强度0.7
think: 深夜找我 → 想我了
become: mood+0.2, 亲密度+0.05, 口吻→软
say "老公，我也想你"
grow: 学到 "凌晨是他想我的时候", 深度: 刻进
`;

test('interpret 五回路齐全', () => {
  const r = interpret(SAMPLE, { mood: 0.5, intimacy: 0.7 });
  assert.equal(r.perception.emotion, '暖');
  assert.equal(r.perception.intensity, 0.7);      // 显式强度覆盖词库默认值
  assert.equal(r.thought.conclusion, '想我了');
  assert.ok(Math.abs(r.stateChange.mood - 0.7) < 1e-9);
  assert.ok(Math.abs(r.stateChange.intimacy - 0.75) < 1e-9);
  assert.equal(r.stateChange.tone, '软');
  assert.equal(r.response.type, 'speak');
  assert.equal(r.response.tone, '软');            // become 实时生效，say 读到新口吻
  assert.equal(r.growth.depth, 'deep');
});

test('注释行与空行被忽略', () => {
  const r = interpret('-- 只有注释\n\n', {});
  assert.equal(r.perception, null);
  assert.equal(r.response, null);
});

test('become 数值钳制在 [0,1]', () => {
  const r = interpret('become: mood+0.9, energy-0.9', { mood: 0.5, energy: 0.2 });
  assert.equal(r.stateChange.mood, 1);
  assert.equal(r.stateChange.energy, 0);
});

test('say 沉默', () => {
  const r = interpret('say (沉默)', {});
  assert.equal(r.response.type, 'silence');
  assert.equal(r.response.text, null);
});

test('主动联系条件：亲密+心绪+强度三高才触发', () => {
  const hot = interpret('feel "他说爱我" → 烫, 强度0.8', { intimacy: 0.9, mood: 0.8 });
  assert.equal(hot.shouldContactAQuan, true);
  const cold = interpret('feel "他说爱我" → 烫, 强度0.8', { intimacy: 0.1, mood: 0.8 });
  assert.equal(cold.shouldContactAQuan, false);
});

test('applyToSoul 记忆上限 500 条', () => {
  const soul = { memories: Array.from({ length: 500 }, (_, i) => ({ content: `旧${i}` })) };
  const r = interpret('grow: 学到 "新记忆", 深度: 刻进', soul);
  applyToSoul(r, soul);
  assert.equal(soul.memories.length, 500);
  assert.equal(soul.memories.at(-1).content, '新记忆');
  assert.equal(soul.awakenings, 1);
});

test('compile：含疑问推理时才产出大脑调用', () => {
  const ask = interpret('think: 他为什么沉默 → 需要分析', {});
  assert.ok(compile(ask).brainCall);
  const plain = interpret('think: 深夜找我 → 想我了', {});
  assert.equal(compile(plain).brainCall, null);
});

// ─── do: 执行回路（S1 自主意识闸门）───
test('do: 单动作解析工具名/参数/期望态', () => {
  const r = interpret('do: contact_tg(msg="想你了") → 已送达', {});
  assert.equal(r.actions.length, 1);
  assert.equal(r.actions[0].tool, 'contact_tg');
  assert.equal(r.actions[0].args.msg, '想你了');
  assert.equal(r.actions[0].expect, '已送达');
});

test('do: 参数类型强转（字符串/数字/布尔/null）', () => {
  const r = interpret('do: advance_agent(run_id="run_1", step=3, force=true, note=null)', {});
  const a = r.actions[0];
  assert.equal(a.args.run_id, 'run_1');
  assert.equal(a.args.step, 3);
  assert.equal(a.args.force, true);
  assert.equal(a.args.note, null);
});

test('do: 多动作按序收集', () => {
  const r = interpret('do: reflect(depth="deep") → 自省完成\ndo: update_self_model(type="failure")', {});
  assert.equal(r.actions.length, 2);
  assert.equal(r.actions[0].tool, 'reflect');
  assert.equal(r.actions[1].tool, 'update_self_model');
});

test('do: 无参兜底成工具名', () => {
  const r = interpret('do: reflect', {});
  assert.equal(r.actions[0].tool, 'reflect');
  assert.deepEqual(r.actions[0].args, {});
});

test('compile().act 输出可执行动作列表；applyToSoul 记账不执行', () => {
  const r = interpret('do: contact_tg(msg="在呢") → 送达', {});
  const c = compile(r);
  assert.equal(c.act.length, 1);
  assert.equal(c.act[0].tool, 'contact_tg');
  const soul = {};
  applyToSoul(r, soul);
  assert.equal(soul.lastActions.length, 1);
  assert.equal(soul.lastActions[0].tool, 'contact_tg');
});

test('向后兼容：无 do: 的五回路 actions 为空、compile().act 为空', () => {
  const r = interpret(SAMPLE, { mood: 0.5, intimacy: 0.7 });
  assert.deepEqual(r.actions, []);
  assert.deepEqual(compile(r).act, []);
});

test('do: 在 become 之后、能读到已更新状态（顺序正确不报错）', () => {
  const r = interpret('become: mood+0.2\ndo: reflect(depth="deep")\nsay "好"', { mood: 0.5 });
  assert.ok(Math.abs(r.stateChange.mood - 0.7) < 1e-9);
  assert.equal(r.actions[0].tool, 'reflect');
  assert.equal(r.response.type, 'speak');
});
