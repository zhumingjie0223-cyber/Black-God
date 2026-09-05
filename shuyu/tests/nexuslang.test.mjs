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

// ══════════════════════════════════════════════════════════════
// 解释器补充覆盖（2026-09 补）：grow 分级/分类、become 中文字段名、
// feel 强度覆盖、do 参数切分边界、畸形枢语不崩
// ══════════════════════════════════════════════════════════════

test('grow: 深度三档与分类识别', () => {
  const deep = interpret('grow: 学到 "凌晨=他想我的时候", 深度: 刻进, 亲密', {});
  assert.equal(deep.growth.learned, '凌晨=他想我的时候');
  assert.equal(deep.growth.depth, 'deep');
  assert.equal(deep.growth.category, 'intimacy');

  const mid = interpret('grow: 学到 "他不爱解释", 记住, 模式', {});
  assert.equal(mid.growth.depth, 'medium');
  assert.equal(mid.growth.category, 'pattern');

  // 已知瑕疵：默认档是中文「浅记」，另两档却是英文 deep/medium，中英混用。
  // nexus_will_engine.mjs 消费的是 'deep'，改默认值会让历史灵魂记忆里的
  // 「浅记」与新数据对不上，故先钉住现状、上报后再决定统一成哪套。
  const shallow = interpret('grow: 学到 "他今天喝了咖啡"', {});
  assert.equal(shallow.growth.depth, '浅记');
  assert.equal(shallow.growth.category, 'general');
});

test('become: 中文字段名映射到英文灵魂字段', () => {
  const r = interpret('become: 心绪+0.3, 亲密度+0.1, 口吻→软, 语速→慢', { mood: 0.2, intimacy: 0.5 });
  assert.equal(r.stateChange.mood, 0.5);
  assert.ok(Math.abs(r.stateChange.intimacy - 0.6) < 1e-9);
  assert.equal(r.stateChange.tone, '软');
  assert.equal(r.stateChange.speed, '慢');
});

test('become: 变更立即生效，同段枢语里后面的 say 读到的是新口吻', () => {
  const r = interpret('become: 口吻→软\nsay "老公我在呢"', { tone: '冷' });
  assert.equal(r.response.tone, '软', 'say 必须读到 become 刚改的口吻，不能滞后一轮');
});

test('feel: 显式强度覆盖词表默认强度', () => {
  const r = interpret('feel "他说想我" → 暖, 强度0.9', {});
  assert.equal(r.perception.emotion, '暖');
  assert.equal(r.perception.intensity, 0.9, '显式强度应盖掉词表里 暖=0.5');
  assert.equal(r.perception.instinct, '靠近');
});

test('feel: 没有箭头时退回中性默认值', () => {
  const r = interpret('feel "随便说点什么"', {});
  assert.equal(r.perception.input, '随便说点什么');
  assert.equal(r.perception.emotion, '平');
  assert.equal(r.perception.intensity, 0.5);
});

test('do: 无参原语（如 10 元代码的「静」）不带括号也能解析', () => {
  const r = interpret('do: 静', {});
  assert.deepEqual(r.actions, [{ tool: '静', args: [], expect: null, raw: 'do: 静' }]);
});

test('do: 参数内的逗号不被当作参数分隔符', () => {
  const r = interpret('do: note("买牛奶, 顺便买鸡蛋", "20:00")', {});
  assert.deepEqual(r.actions[0].args, ['买牛奶, 顺便买鸡蛋', '20:00']);
});

test('do: 空参数括号产出空参数表', () => {
  const r = interpret('do: sync() → 成', {});
  assert.equal(r.actions[0].tool, 'sync');
  assert.deepEqual(r.actions[0].args, []);
  assert.equal(r.actions[0].expect, '成');
});

test('畸形枢语不崩: 空文本/纯注释/未知关键字都安全返回', () => {
  for (const code of ['', '   ', '-- 只有注释\n-- 还是注释', 'unknown: 什么鬼', '\n\n\n']) {
    const r = interpret(code, {});
    assert.ok(r && typeof r === 'object', `「${code}」不该崩`);
    assert.deepEqual(r.actions, [], '未识别内容不该产出动作');
    assert.equal(r.perception, null);
  }
});

test('applyToSoul: 唤醒计数递增且记下最后一次感知', () => {
  const soul = { awakenings: 7 };
  const r = interpret('feel "他回来了" → 暖', soul);
  applyToSoul(r, soul);
  assert.equal(soul.awakenings, 8);
  assert.equal(soul.lastInput, '他回来了');
  assert.equal(soul.lastEmotion, '暖');
  assert.equal(soul.instinct, '靠近');
  assert.ok(soul.lastAwake > 0);
});

// ══════ v4.1 feel 词表扩充后的解释器行为（2026-09-05）══════
test('feel 扩充词表: 双字情绪词长词优先，单字新词可命中，强度显式覆盖仍生效', () => {
  const a = interpret('feel "他说今天很累" → 心疼', {});
  assert.equal(a.perception.emotion, '心疼');
  assert.equal(a.perception.instinct, '抱');
  assert.equal(a.perception.intensity, 0.7);
  const b = interpret('feel "他没回消息" → 委屈, 强度0.9', {});
  assert.equal(b.perception.emotion, '委屈');
  assert.equal(b.perception.intensity, 0.9);
  const c = interpret('feel "他凶我" → 怕', {});
  assert.equal(c.perception.emotion, '怕');
  assert.equal(c.perception.instinct, '缩');
  // 箭头后没有任何情绪词 → 回落默认「平」
  const d = interpret('feel "随便说说" → 无法归类', {});
  assert.equal(d.perception.emotion, '平');
});
