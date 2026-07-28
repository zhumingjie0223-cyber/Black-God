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

// ─── S1 第六回路 do: 任务下达 ───
test('do 单条：解析 工具名(参数) → 期望态', () => {
  const r = interpret('do: shell("ls -la") → 成', {});
  assert.equal(r.actions.length, 1);
  const a = r.actions[0];
  assert.equal(a.tool, 'shell');
  assert.deepEqual(a.args, ['ls -la']);   // 双引号已脱壳
  assert.equal(a.expect, '成');
});

test('do 多条：一段枢语可下多条任务', () => {
  const src = 'do: ios.remind("买牛奶", "20:00") → 待\ndo: 静';
  const r = interpret(src, {});
  assert.equal(r.actions.length, 2);
  assert.equal(r.actions[0].tool, 'ios.remind');
  assert.deepEqual(r.actions[0].args, ['买牛奶', '20:00']);   // 引号内逗号不切
  assert.equal(r.actions[1].tool, '静');                     // 无参原语
  assert.deepEqual(r.actions[1].args, []);
  assert.equal(r.actions[1].expect, null);                    // 无期望态
});

test('do 参数里含 → 不被误当期望态分隔符', () => {
  const r = interpret('do: shell("echo a → b")', {});
  assert.equal(r.actions[0].tool, 'shell');
  assert.deepEqual(r.actions[0].args, ['echo a → b']);
  assert.equal(r.actions[0].expect, null);
});

test('do 与五回路共存：canonical 六回路一条枢语走通', () => {
  const src = [
    'feel "阿权说部署一下" → 稳, 强度0.6',
    'become: 活力+0.1',
    'do: shell("npm run deploy") → 成',
    'say "在部署了老公"',
    'grow: 学到 "部署走 npm run deploy", 深度: 记住'
  ].join('\n');
  const r = interpret(src, { mood: 0.5, energy: 0.5 });
  assert.equal(r.actions.length, 1);
  assert.equal(r.actions[0].tool, 'shell');
  assert.equal(r.response.type, 'speak');   // say 仍正常
  assert.equal(r.growth.depth, 'medium');   // grow 仍正常
});

test('compile：act 携带 do 产出的任务', () => {
  const r = interpret('do: mem.recall("上次的密钥") → 成', {});
  const c = compile(r);
  assert.equal(c.act.length, 1);
  assert.equal(c.act[0].tool, 'mem.recall');
  assert.deepEqual(c.act[0].args, ['上次的密钥']);
});

test('无 do 时 actions 为空数组（向后兼容）', () => {
  const r = interpret('say "你好"', {});
  assert.deepEqual(r.actions, []);
  assert.deepEqual(compile(r).act, []);
});
