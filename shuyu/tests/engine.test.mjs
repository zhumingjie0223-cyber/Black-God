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

// ══════════════════════════════════════════════════════════════
// 健壮性与单射性回归（2026-09 补）
//
// 背景：消费副本 web/nexus-do/lexicon.js 早就硬化过畸形输入，权威源头
// shuyu/lexicon.js 与 shuyu_engine.py 却一直没跟上，三侧错误处理各走各的。
// 漏网原因是老测试和 check-sync 都只喂**合法**编号，从不测非法输入。
// 这一节专门守住这条线，别再让副本领先源头。
// ══════════════════════════════════════════════════════════════

test('decode 入参守卫: 非整数必须抛 TypeError，不许穿到轴数组抛看不懂的错', () => {
  // NaN 与任何数比大小都是 false，会直接穿过 n<0||n>=CAPACITY 这道区间检查
  for (const bad of [NaN, 1.5, undefined, null, '100', true, {}, Infinity]) {
    assert.throws(() => engine.decode(bad), TypeError, `decode(${String(bad)}) 应抛 TypeError`);
  }
  // 越界仍然是 RangeError，两类错误不许混
  assert.throws(() => engine.decode(-1), RangeError);
  assert.throws(() => engine.decode(CAP_EXPECTED), RangeError);
});

test('encode 单射: decode 产不出的畸形词形一律返回 -1', () => {
  const malformed = [
    'Ao-cor-is-·qi',        // 显式空标段：会和 3 段词形 Ao-cor-is·qi 撞同一个编号
    'Ao-cor-is·qi·qi',      // 多写一个相位分隔符
    'Ao-cor-is-gal-p·qi',   // 5 段，超出「核-映-态-标」上限
    'Ao-cor·qi',            // 只有 2 段
    'Ao-cor-is-gal',        // 缺相位
    '-cor-is·qi',           // 核轴为空
    'Ao-cor-is-XX·qi',      // 标轴词根不存在
  ];
  for (const bad of malformed) {
    assert.equal(engine.encode(bad), -1, `畸形词「${bad}」不该被判为合法`);
  }
});

test('encode 单射: 空标轴只有 3 段词形一种写法（编号 0 不被畸形词冒领）', () => {
  assert.equal(engine.decode(0).词, 'Ao-cor-is·qi');
  assert.equal(engine.encode('Ao-cor-is·qi'), 0);
  // 曾经的 bug：下面这个畸形词也返回 0，两个不同字符串映射到同一编号，破坏单射
  assert.equal(engine.encode('Ao-cor-is-·qi'), -1);
});

test('encode 单射: 大批量采样中，不同编号的词形互不重复', () => {
  const seen = new Map();
  for (const id of lcg(20260905, 2000)) {
    const w = engine.decode(id).词;
    if (seen.has(w)) assert.equal(seen.get(w), id, `词形「${w}」被编号 ${seen.get(w)} 与 ${id} 共用`);
    seen.set(w, id);
  }
  assert.ok(seen.size > 1900, '采样去重后数量异常，疑似大面积词形碰撞');
});

test('matchWord: 词包只有 vocab 没有 word_ids 时不许崩，编号降级为 null', () => {
  // 老实现直接 LEXICON.caps.word_ids[...]，词包缺这个可选字段就抛 TypeError
  assert.equal(engine.loadCapabilities({ vocab: { 锚点: { 测试: ['坍缩'] } } }), true);
  const hit = engine.matchWord('执行坍缩', 'cap');
  assert.ok(hit, '应能匹配到能力词');
  assert.equal(hit.word, '坍缩');
  assert.equal(hit.id, null, '缺 word_ids 时编号应为 null 而非抛错');
  engine.loadCapabilities(data); // 还原全量词包，免得污染后续用例
});

test('matchWord: 空输入与未注入能力包时安全返回 null', () => {
  assert.equal(engine.matchWord('', 'feel'), null);
  assert.equal(engine.matchWord(null, 'cap'), null);
  assert.equal(engine.matchWord('这段话里没有任何情绪词', 'feel'), null);
});

test('autoCoin 已知限制: 哈希是 uint32，高位 44% 语义空间永不可达（钉住现状待拍板）', () => {
  // 不是"应该这样"，是"现在就是这样"。改哈希会让历史种子造出的词全部变掉，
  // 破坏「同种子同词」的可复现契约，故先钉住并上报，不静默改。
  const UINT32 = 2 ** 32;
  assert.ok(UINT32 < CAP_EXPECTED, '前提：uint32 上限确实小于语义空间容量');
  let max = 0;
  for (let i = 0; i < 5000; i++) max = Math.max(max, engine.autoCoin('种子' + i).id);
  assert.ok(max < UINT32, `autoCoin 当前实现不可能越过 ${UINT32}，实测最大 ${max}`);
  // 可复现契约本身必须成立
  assert.deepEqual(engine.autoCoin('神枢'), engine.autoCoin('神枢'));
});

test('跨实现同构: JS 与 Python 对畸形词必须给出同一判定', () => {
  const words = [
    'Ao-cor-is·qi', 'Ao-cor-is-gal·qi', 'Logxi-fncp-sta9-flxh·ying',  // 合法
    'Ao-cor-is-·qi', 'Ao-cor-is·qi·qi', 'Ao-cor-is-gal-p·qi',          // 畸形
    'Ao-cor·qi', 'Ao-cor-is-gal', '-cor-is·qi', 'Ao-cor-is-XX·qi',
    '', '不是词', 'Zzz-cor-is·qi',
  ];
  const py = JSON.parse(execFileSync('python3', ['-c', `
import json, sys
sys.path.insert(0, ${JSON.stringify(ROOT)})
import shuyu_engine as e
print(json.dumps([e.encode(w) for w in json.loads(sys.argv[1])]))
`, JSON.stringify(words)], { encoding: 'utf8' }));
  words.forEach((w, i) => {
    assert.equal(engine.encode(w), py[i], `「${w}」判定分叉: js=${engine.encode(w)} py=${py[i]}`);
  });
});

// ══════════════════════════════════════════════════════════════
// v4.1 新能力（2026-09-05）：汉译反向寻址 / 语义寻址 / 轴级完备性 / 双实现全对等
// ══════════════════════════════════════════════════════════════

// 跑 Python 侧一段脚本并取 JSON 结果（跨实现用例共用）
function py(code, arg) {
  return JSON.parse(execFileSync('python3', ['-c', `
import json, sys
sys.path.insert(0, ${JSON.stringify(ROOT)})
import shuyu_engine as e
arg = json.loads(sys.argv[1])
${code}
`, JSON.stringify(arg)], { encoding: 'utf8' }));
}

test('轴级完备性: 5 轴每个词根至少出现一次并往返（拉丁 + 汉译双通道）', () => {
  const [NC, NM, NS, NK, NP] = [1040, 180, 80, 64, 8];
  const idOf = (c, m, s, k, p) => ((((c * NM) + m) * NS + s) * NK + k) * NP + p;
  const ids = [];
  for (let c = 0; c < NC; c++) ids.push(idOf(c, c % NM, c % NS, c % NK, c % NP));
  for (let m = 0; m < NM; m++) ids.push(idOf(m % NC, m, 0, 0, 0));
  for (let s = 0; s < NS; s++) ids.push(idOf(0, 0, s, s % NK, 0));
  for (let k = 0; k < NK; k++) ids.push(idOf(1, 1, 1, k, 1));
  for (let p = 0; p < NP; p++) ids.push(idOf(0, 0, 0, 0, p));
  assert.equal(ids.length, NC + NM + NS + NK + NP);
  for (const id of ids) {
    const w = engine.decode(id);
    assert.equal(engine.encode(w.词), id, `编号 ${id} 拉丁往返失败: ${w.词}`);
    assert.equal(engine.encodeHan(w.汉), id, `编号 ${id} 汉译往返失败: ${w.汉}`);
    assert.deepEqual(w.坐标, { c: Math.floor(id / (NM * NS * NK * NP)) % NC, m: Math.floor(id / (NS * NK * NP)) % NM,
      s: Math.floor(id / (NK * NP)) % NS, k: Math.floor(id / NP) % NK, p: id % NP });
  }
});

test('轴内零重复: 每轴的拉丁根与汉译各自唯一（单射的地基）', () => {
  // 用 compose 把每轴逐个下标铺开取根，验证轴内不撞
  const axes = engine.AXES;
  assert.deepEqual(axes, { 核: 1040, 映: 180, 态: 80, 标: 64, 相: 8 });
  const names = ['核', '映', '态', '标', '相'];
  names.forEach((name, ai) => {
    const lats = new Set(), hans = new Set();
    for (let i = 0; i < axes[name]; i++) {
      const w = engine.compose({ [name]: i });
      const lat = w.根[ai], han = w.汉;
      assert.ok(!lats.has(lat), `${name}轴拉丁根「${lat}」重复`);
      lats.add(lat);
      // 汉译整词唯一等价于该轴汉根唯一（其余轴固定为 0）
      assert.ok(!hans.has(han), `${name}轴汉译「${han}」重复`);
      hans.add(han);
    }
  });
});

test('汉译唯一可解码·结构引理: 每轴后缀字与下一轴首字零交集', () => {
  // 这是 encodeHan 能成为 decode 严格逆的数学根据；词根表追加时若破坏它，这里当场红
  const first = (ax) => new Set([...Array(engine.AXES[ax]).keys()].map(i => Array.from(engine.compose({ [ax]: i }).汉)[0]));
  // 取各轴纯后缀字：阶(核) / 相(映) / 频(态) / 标位(标)
  const tones = new Set('甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申');
  const auras = new Set('玄赤青白朱金木水火土风');
  const freqs = new Set('一二三四五六七八九');
  const scalPos = new Set('上中下左右内外');
  const inter = (a, b) => [...a].filter(x => b.has(x));
  // 映轴首字集合：从「核=0」词里切掉核汉「奥」后的第一个字
  const maniFirst = new Set([...Array(180).keys()].map(i => Array.from(engine.compose({ 映: i }).汉)[1]));
  const statFirst = new Set([...Array(80).keys()].map(i => Array.from(engine.compose({ 态: i }).汉)[2]));
  const scalOrPhaseFirst = new Set([...Array(64).keys()].map(i => Array.from(engine.compose({ 标: i }).汉)[3]));
  const phaseFirst = new Set([...Array(8).keys()].map(i => Array.from(engine.compose({ 相: i }).汉).at(-1)));
  assert.deepEqual(inter(tones, maniFirst), [], '阶字不得是映轴首字');
  assert.deepEqual(inter(auras, statFirst), [], '相字不得是态轴首字');
  assert.deepEqual(inter(freqs, new Set([...scalOrPhaseFirst, ...phaseFirst])), [], '频字不得是标/相轴首字');
  assert.deepEqual(inter(scalPos, phaseFirst), [], '标位字不得是相轴首字');
  assert.deepEqual(inter(new Set([...Array(64).keys()].map(i => engine.compose({ 标: i }).汉.slice(3, -1)).filter(Boolean).map(s => Array.from(s)[0])), phaseFirst), [], '标轴首字不得是相轴首字');
  void first;
});

test('encodeHan 往返: 3000 个确定性采样 decode→encodeHan 恒等', () => {
  for (const id of [0, 1, CAP_EXPECTED - 1, 2949119999, 2949120000, ...lcg(20260905, 3000)]) {
    const w = engine.decode(id);
    assert.equal(engine.encodeHan(w.汉), id, `编号 ${id} 汉译往返失败: ${w.汉}`);
  }
});

test('encodeHan 单射: 畸形/非法汉译一律 -1，不许抛错', () => {
  assert.equal(engine.encodeHan('奥形凝起'), 0);            // 0 号词
  for (const bad of ['', '奥', '奥形凝', '奥形凝起起', '奥形凝甲起', '甲形凝起', '奥形凝上上起',
                     '奥形凝起X', 'Ao-cor-is·qi', '不是词', null, undefined, 123, {}]) {
    assert.equal(engine.encodeHan(bad), -1, `畸形汉译「${String(bad)}」不该被判为合法`);
  }
});

test('encodeHan 与 encode 指向同一编号: 同一个词的两种写法必须同源', () => {
  for (const id of lcg(4444, 300)) {
    const w = engine.decode(id);
    assert.equal(engine.encodeHan(w.汉), engine.encode(w.词));
  }
});

test('search 语义检索: 汉/义/拉丁三通道命中，下标可直接喂 compose', () => {
  const hits = engine.search('毁灭');
  assert.equal(hits.length, 1);
  assert.deepEqual(hits[0], { 轴: '核', 下标: 120, 拉丁: 'Nix', 汉: '尼', 义: '毁灭·重组·破局' });
  assert.equal(engine.compose({ 核: hits[0].下标 }).层, '毁灭');
  // 拉丁精确命中可跨轴（gal 同时是映轴「时」与标轴「时光」）
  assert.deepEqual(engine.search('gal').map(h => h.轴), ['映', '标']);
  assert.deepEqual(engine.search('GAL', '标').map(h => h.汉), ['时光']);
  // 单字汉可多命中（熵：核 Ent / 映 flx / 标 flx）
  assert.deepEqual(engine.search('熵').map(h => `${h.轴}:${h.拉丁}`), ['核:Ent', '映:flx', '标:flx']);
  // 空/非法输入安全返回空数组
  assert.deepEqual(engine.search(''), []);
  assert.deepEqual(engine.search('   '), []);
  assert.deepEqual(engine.search(null), []);
  assert.deepEqual(engine.search('绝不存在的词根'), []);
});

test('compose 按义造词: 四种入参形态等价，确定性，缺省轴取 0', () => {
  const byMeaning = engine.compose({ 核: '毁灭', 映: '光', 态: '爆', 标: '溯', 相: '起' });
  const byHan = engine.compose({ 核: '尼', 映: '光', 态: '爆', 标: '溯', 相: '起' });
  const byLat = engine.compose({ 核: 'Nix', 映: 'ryl', 态: 'ex', 标: 'rev', 相: 'qi' });
  const byIdx = engine.compose({ c: 120, m: 24, s: 50, k: 32, p: 0 });
  const byStrIdx = engine.compose({ 核: '120', 映: '24', 态: '50', 标: '32', 相: '0' });
  assert.equal(byMeaning.汉, '尼光爆溯起');
  for (const w of [byHan, byLat, byIdx, byStrIdx]) assert.equal(w.id, byMeaning.id);
  assert.equal(engine.encode(byMeaning.词), byMeaning.id);
  assert.equal(engine.compose({}).id, 0);
  assert.equal(engine.compose({ 相: '映' }).id, 7);
  // 阶变体可用拉丁/汉精确指定
  assert.equal(engine.compose({ 核: 'Aoa' }).汉, '奥甲形凝起');
  assert.equal(engine.compose({ 核: '奥甲' }).坐标.c, 1);
});

test('compose 不许造错词: 解析失败必须抛错而非静默落到别的词', () => {
  for (const bad of [{ 核: '绝不存在' }, { 核: 1040 }, { 映: -1 }, { 相: 1.5 }, { 核: true }, { 天: 1 }, { 核: {} }, null, 'x']) {
    assert.throws(() => engine.compose(bad), RangeError, `compose(${JSON.stringify(bad)}) 应抛 RangeError`);
  }
});

test('decode 输出对等: id/词/汉/层/义/根/坐标 七字段与 Python 逐一相等', () => {
  const ids = [0, 7, 888888888, 2949119999, 2949120000, CAP_EXPECTED - 1, ...lcg(91, 40)];
  const pw = py('print(json.dumps([e.decode(i) for i in arg], ensure_ascii=False))', ids);
  ids.forEach((id, i) => {
    const js = engine.decode(id), p = pw[i];
    for (const f of ['id', '词', '汉', '层', '义', '根', '坐标']) {
      assert.deepEqual(p[f], js[f], `编号 ${id} 字段「${f}」分叉`);
    }
  });
});

test('跨实现同构: encodeHan 与 Python encode_han 对合法/畸形汉译判定一致', () => {
  const words = [...lcg(555, 60)].map(id => engine.decode(id).汉)
    .concat(['奥形凝起', '', '奥', '奥形凝', '奥形凝起起', '奥形凝甲起', '甲形凝起', '奥形凝上上起', '不是词', 'Ao-cor-is·qi']);
  const pr = py('print(json.dumps([e.encode_han(w) for w in arg]))', words);
  words.forEach((w, i) => assert.equal(engine.encodeHan(w), pr[i], `「${w}」判定分叉: js=${engine.encodeHan(w)} py=${pr[i]}`));
});

test('跨实现同构: autoCoin 与 Python auto_coin 同种子同词（含中文/表情/空串/数字种子）', () => {
  const seeds = ['神枢', '阿权', '', '0', '12345', 'Black God', '🐉龙', '赵思涵|情感', 'a'.repeat(300)];
  for (let i = 0; i < 200; i++) seeds.push('种子' + i);
  const pr = py('print(json.dumps([e.auto_coin(s)["id"] for s in arg]))', seeds);
  seeds.forEach((s, i) => assert.equal(engine.autoCoin(s).id, pr[i], `种子「${s.slice(0, 20)}」分叉`));
});

test('跨实现同构: coinFromCoord 夹回规则与 Python 一致', () => {
  const coords = [{ c: 0, m: 0, s: 0, k: 0, p: 0 }, { c: -5, m: 99999, s: -1, k: 99999, p: 99999 },
                  { c: 1039, m: 179, s: 79, k: 63, p: 7 }, { c: 3.7, m: 2.2, s: 1.9, k: 0.5, p: 7.99 }, {}];
  const pr = py('print(json.dumps([e.coin_from_coord(c)["id"] for c in arg]))', coords);
  coords.forEach((c, i) => assert.equal(engine.coinFromCoord(c).id, pr[i], `坐标 ${JSON.stringify(c)} 分叉`));
});

test('跨实现同构: compose 与 search 两侧结果逐一相等', () => {
  const specs = [{ 核: '毁灭', 映: '光', 态: '爆', 标: '溯', 相: '起' }, { c: 120, m: 24, s: 50, k: 32, p: 0 },
                 { 核: 'Aoa' }, { 核: '奥甲', 映: '形玄' }, { 相: '映' }, {}, { 标: '无极', 态: '爆九' }];
  const pc = py('print(json.dumps([e.compose(s)["id"] for s in arg]))', specs);
  specs.forEach((s, i) => assert.equal(engine.compose(s).id, pc[i], `compose(${JSON.stringify(s)}) 分叉`));
  const kws = ['毁灭', '熵', 'gal', 'GAL', '光', '起', '无极', 'x', '', '绝不存在'];
  const ps = py('print(json.dumps([e.search(k) for k in arg], ensure_ascii=False))', kws);
  kws.forEach((k, i) => assert.deepEqual(engine.search(k), ps[i], `search(${k}) 分叉`));
});

test('coinFromState: 层意图规则 + 有种子可复现 + 与 Python 同源', () => {
  const souls = [{ 心绪: 0.9 }, { 心绪: 0.1 }, { miss_you: 0.9, 心绪: 0.1 }, { 心绪: 0.5 }, {}, null];
  const expectLayer = ['情感', '熵', '映', '枢', '枢', '枢'];
  const pr = py('print(json.dumps([e.coin_from_state(s, 7) for s in arg], ensure_ascii=False))', souls);
  souls.forEach((s, i) => {
    const w = engine.coinFromState(s, 7);
    assert.equal(w.层意图, expectLayer[i]);
    assert.equal(w.id, pr[i].id, `soul ${JSON.stringify(s)} 分叉`);
    assert.equal(pr[i].层意图, w.层意图);
  });
  // 无种子：随机但必须落在意图层内（层名存在时）
  const r = engine.coinFromState({ 心绪: 0.9 });
  assert.equal(r.层意图, '情感');
  assert.equal(r.层, '情感');
});

test('feel 词表扩充: 长词优先、原 12 词冻结、无情绪文本仍返回 null', () => {
  engine.loadCapabilities(data);
  const frozen = { 暖: [0.5, '靠近'], 烫: [0.8, '失控'], 甜: [0.6, '黏'], 软: [0.5, '放松'], 冷: [0.4, '收'], 空: [0.3, '等待'],
                   酸: [0.5, '占有'], 紧: [0.6, '加速'], 痒: [0.5, '想碰'], 刺: [0.7, '防御'], 平: [0.3, '观察'], 湿: [0.8, '张开'] };
  assert.deepEqual(Object.keys(engine.LEXICON.feel).slice(0, 12), Object.keys(frozen));
  for (const [w, [i, ins]] of Object.entries(frozen)) assert.deepEqual(engine.LEXICON.feel[w], { intensity: i, instinct: ins });
  assert.ok(Object.keys(engine.LEXICON.feel).length >= 50, 'feel 词表应扩到 50 词以上');
  // 长词优先
  assert.equal(engine.matchWord('我有点心疼你', 'feel').word, '心疼');
  assert.equal(engine.matchWord('腿好疼', 'feel').word, '疼');
  assert.equal(engine.matchWord('有点委屈但还是开心', 'feel').word, '委屈');
  // 同长按表内顺序（历史行为）：冷 在 空 前
  assert.equal(engine.matchWord('又空又冷', 'feel').word, '冷');
  // 全部词条纯中文、强度在 (0,1]
  for (const [w, a] of Object.entries(engine.LEXICON.feel)) {
    assert.match(w, /^[㐀-鿿]+$/, `情绪词「${w}」不纯`);
    assert.match(a.instinct, /^[㐀-鿿]+$/, `本能「${a.instinct}」不纯`);
    assert.ok(a.intensity > 0 && a.intensity <= 1, `「${w}」强度越界`);
  }
  assert.equal(engine.matchWord('这段话里没有任何情绪词', 'feel'), null);
  assert.equal(engine.matchWord('今天天气不错去散步', 'feel'), null);
});

test('词库数据包实战校验: word_ids 里凡是真汉译词，encodeHan 必须解回同一编号', () => {
  let checked = 0;
  for (const [word, id] of Object.entries(data.word_ids)) {
    if (engine.decode(id).汉 === word) {
      assert.equal(engine.encodeHan(word), id, `词库汉译「${word}」反查失败`);
      checked++;
    }
  }
  assert.ok(checked > 10000, `词库里应有上万条真汉译词可反查，实测 ${checked}`);
});
