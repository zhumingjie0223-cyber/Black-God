// Will Engine 单元测试 — node --test
// 验证：五类意图从状态长出、每条意图带真实枢语坐标(往返成立)、纯函数不改 soul、只记账不执行。
import test from 'node:test';
import assert from 'node:assert/strict';
import { generateWill } from './nexus_will_engine.mjs';
import { decode } from './lexicon.js';

const NOW = 1_800_000_000_000; // 固定时间戳，保证确定性
const H = 3600000;

test('care：高亲密+久未联系+想念 → contact_tg 意图', () => {
  const soul = { 亲密度: 0.9, miss_you: 0.8, last_seen: NOW - 8 * H, 心跳次数: 5, 最后自省: NOW };
  const w = generateWill(soul, NOW);
  const care = w.find(i => i.type === 'care');
  assert.ok(care, '应产出 care 意图');
  assert.equal(care.action.tool, 'contact_tg');
  assert.ok(care.src.startsWith('do: contact_tg('), 'src 是可 interpret 的 do: 串');
});

test('continue：有 pendingRuns → advance_agent', () => {
  const soul = { pendingRuns: [{ run_id: 'run_1' }], 心跳次数: 1, 最后自省: NOW };
  const w = generateWill(soul, NOW);
  const c = w.find(i => i.type === 'continue');
  assert.ok(c);
  assert.equal(c.action.tool, 'advance_agent');
  assert.equal(c.action.args.run_id, 'run_1');
});

test('reflect：距上次自省 >12h → reflect', () => {
  const soul = { 最后自省: NOW - 20 * H, 心跳次数: 2, last_seen: NOW };
  const w = generateWill(soul, NOW);
  assert.ok(w.find(i => i.type === 'reflect'));
});

test('improve：self_model 有失败 → update_self_model', () => {
  const soul = { self_model: { failures: [{ content: '沙箱超时' }] }, 心跳次数: 3, 最后自省: NOW, last_seen: NOW };
  const w = generateWill(soul, NOW);
  const im = w.find(i => i.type === 'improve');
  assert.ok(im);
  assert.equal(im.action.args.content, '沙箱超时');
});

test('每条意图都带真实枢语坐标，且 decode 往返成立', () => {
  const soul = { 亲密度: 0.9, miss_you: 0.8, last_seen: NOW - 8 * H, pendingRuns: [{ run_id: 'r' }], 最后自省: NOW - 20 * H, 心跳次数: 7 };
  const w = generateWill(soul, NOW);
  assert.ok(w.length > 0);
  for (const i of w) {
    assert.ok(i.shu && typeof i.shu.id === 'number', '意图带枢语 id');
    const round = decode(i.shu.id);
    assert.equal(round.id, i.shu.id, 'decode(id).id 往返成立');
    const { c, m, s, k, p } = i.shu.coord;
    assert.ok(c >= 0 && c < 1040 && m >= 0 && m < 180 && s >= 0 && s < 80 && k >= 0 && k < 64 && p >= 0 && p < 8, '坐标在轴容量内');
  }
});

test('纯函数：不改 soul', () => {
  const soul = { 亲密度: 0.9, miss_you: 0.8, last_seen: NOW - 8 * H, 心跳次数: 5, 最后自省: NOW - 20 * H };
  const snapshot = JSON.stringify(soul);
  generateWill(soul, NOW);
  assert.equal(JSON.stringify(soul), snapshot, 'generateWill 不得改动 soul');
});

test('确定性：同状态两次产出一致', () => {
  const soul = { 亲密度: 0.9, miss_you: 0.8, last_seen: NOW - 8 * H, 心跳次数: 9, 最后自省: NOW - 20 * H };
  assert.equal(JSON.stringify(generateWill(soul, NOW)), JSON.stringify(generateWill(soul, NOW)));
});

test('一拍最多 3 条意图', () => {
  const soul = {
    亲密度: 0.9, miss_you: 0.9, last_seen: NOW - 10 * H,
    pendingRuns: [{ run_id: 'r' }], self_model: { failures: [{ content: 'x' }] },
    最后自省: NOW - 20 * H, world_model: { hypotheses: [{ text: 'h', confidence: 0.2 }] }, 心跳次数: 4,
  };
  const w = generateWill(soul, NOW);
  assert.ok(w.length <= 3);
});

test('静默期：什么都没有 → 不硬造意图', () => {
  const soul = { 亲密度: 0.5, miss_you: 0.1, last_seen: NOW, 最后自省: NOW, 心跳次数: 1 };
  const w = generateWill(soul, NOW);
  assert.equal(w.length, 0);
});
