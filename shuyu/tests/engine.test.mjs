// 枢语引擎测试（Node 侧）— 引擎数学正确性 / 往返寻址 / 词库数据包 / 跨实现一致性
// 运行: npm test  (即 node --test tests/)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const engine = (await import(path.join(ROOT, 'lexicon.js'))).default;
const data = (await import(path.join(ROOT, 'lexicon_data.js'))).default;

const CAP_EXPECTED = 1040 * 180 * 80 * 64 * 8; // 7,667,712,000

// 确定性伪随机（不用 Math.random，保证可复现）
function* lcg(seed, n) {
  let x = BigInt(seed);
  const a = 6364136223846793005n, c = 1442695040888963407n, m = 1n << 64n;
  for (let i = 0; i < n; i++) { x = (a * x + c) % m; yield Number(x % BigInt(CAP_EXPECTED)); }
}

test('容量恒等: 核1040×映180×态80×标64×相8 = 7,667,712,000', () => {
  assert.equal(engine.CAPACITY, CAP_EXPECTED);
});

test('边界解码: 0 与 容量-1 均可解，越界必须抛错', () => {
  const first = engine.decode(0);
  assert.equal(first.id, 0);
  assert.equal(first.词, 'Ao-cor-is·qi');
  assert.equal(first.汉, '奥形凝起');
  const last = engine.decode(CAP_EXPECTED - 1);
  assert.equal(last.id, CAP_EXPECTED - 1);
  assert.throws(() => engine.decode(-1), RangeError);
  assert.throws(() => engine.decode(CAP_EXPECTED), RangeError);
});

test('往返恒等: decode→encode 必须成立（500 个确定性采样 + 边界）', () => {
  const ids = [0, 1, CAP_EXPECTED - 1, 2949120000, ...lcg(20260712, 500)];
  for (const id of ids) {
    const w = engine.decode(id);
    assert.equal(engine.encode(w.词), id, `编号 ${id} 往返失败: ${w.词}`);
  }
});

test('汉译纯中文: 汉字段不得混入英文/数字/符号', () => {
  const pure = /^[㐀-鿿]+$/;
  for (const id of [0, CAP_EXPECTED - 1, ...lcg(42, 300)]) {
    const w = engine.decode(id);
    assert.match(w.汉, pure, `编号 ${id} 汉译不纯: ${w.汉}`);
  }
});

test('词形规范: 核-映-态(-标)·相', () => {
  const shape = /^[A-Za-z]+-[a-z0-9]+-[a-z0-9]+(-[a-z0-9]+)?·[a-z]+$/;
  for (const id of lcg(7, 300)) {
    const w = engine.decode(id);
    assert.match(w.词, shape, `编号 ${id} 词形异常: ${w.词}`);
  }
});

test('非法词编码必须返回 -1，不许抛错', () => {
  for (const bad of ['', '不是词', 'Ao-cor', 'Zzz-cor-is·qi', 'Ao-cor-is·zzz']) {
    assert.equal(engine.encode(bad), -1);
  }
});

test('追加式铁律: v4 扩充区间(≥29.5亿)首词与旧区间末词都不动摇', () => {
  // 旧区间末词（29.5亿-1）与 v4 区间首词（29.5亿）是历史锚点，任何重排都会破坏这里
  const oldLast = engine.decode(2949119999);
  assert.equal(oldLast.词, 'Logxi-fncp-sta9-flxh·ying');
  const v4First = engine.decode(2949120000);
  assert.equal(v4First.词, 'Aur-cor-is·qi');
  assert.equal(v4First.汉, '曜形凝起');
});

test('确定性造词 autoCoin: 同种子同词，可复现', () => {
  const a = engine.autoCoin('神枢');
  const b = engine.autoCoin('神枢');
  assert.deepEqual(a, b);
  assert.ok(a.id >= 0 && a.id < CAP_EXPECTED);
});

test('坐标造词 coinFromCoord: 原点=0号词，越界坐标必须夹回合法区间', () => {
  assert.equal(engine.coinFromCoord({ c: 0, m: 0, s: 0, k: 0, p: 0 }).id, 0);
  const clamped = engine.coinFromCoord({ c: -5, m: 99999, s: -1, k: 99999, p: 99999 });
  assert.ok(clamped.id >= 0 && clamped.id < CAP_EXPECTED);
});

test('词库数据包: 元信息容量与引擎一致，编号全部在界内', () => {
  assert.equal(data.meta.引擎容量, engine.CAPACITY);
  const entries = Object.entries(data.word_ids);
  assert.ok(entries.length > 0, 'word_ids 不能为空');
  for (const [word, id] of entries) {
    assert.ok(Number.isInteger(id) && id >= 0 && id < engine.CAPACITY, `词「${word}」编号越界: ${id}`);
  }
});

test('能力注入 + 词匹配: loadCapabilities 后 feel/cap 两层都能召回', () => {
  assert.equal(engine.loadCapabilities(data), true);
  const feel = engine.matchWord('今天心里暖暖的', 'feel');
  assert.ok(feel && feel.word === '暖' && feel.instinct === '靠近');
  // 从词库任取一个能力词验证 cap 匹配
  const anyWord = Object.keys(data.word_ids)[0];
  const cap = engine.matchWord(`测试${anyWord}测试`, 'cap');
  assert.ok(cap && cap.word.length > 0, 'cap 层应能匹配到能力词');
});

test('跨实现同构: Python 与 JS 同一编号必须解出同一个词', () => {
  const ids = [0, 1, 2949119999, 2949120000, CAP_EXPECTED - 1, ...lcg(1040, 60)];
  const py = execFileSync('python3', ['-c', `
import json, sys
sys.path.insert(0, ${JSON.stringify(ROOT)})
import shuyu_engine as e
ids = json.loads(sys.argv[1])
print(json.dumps([e.decode_full(i) for i in ids], ensure_ascii=False))
`, JSON.stringify(ids)], { encoding: 'utf8' });
  const pyWords = JSON.parse(py);
  ids.forEach((id, i) => {
    const js = engine.decode(id), p = pyWords[i];
    assert.equal(p.词, js.词, `编号 ${id} 拉丁词形分叉: py=${p.词} js=${js.词}`);
    assert.equal(p.汉, js.汉, `编号 ${id} 汉译分叉: py=${p.汉} js=${js.汉}`);
    assert.equal(p.层, js.层, `编号 ${id} 层分叉: py=${p.层} js=${js.层}`);
    assert.equal(p.义, js.义, `编号 ${id} 语义分叉: py=${p.义} js=${js.义}`);
  });
});
