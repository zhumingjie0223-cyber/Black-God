#!/usr/bin/env node
// 与 shuyu-lang 源头引擎同步校验(Black God 消费方侧)
// 用法: node tools/check-sync.mjs [shuyu-lang仓路径]   默认依次尝试 ../shuyu-lang、../Shuyu-Lang
// 找得到源头仓 → 全量比对(容量/五轴词根/抽样解码/接口/数据包);
// 找不到(如 CI 单仓环境)→ 退化为内置黄金指纹自检,保证本仓副本没被改坏。
import { existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

const HERE = resolve(new URL('..', import.meta.url).pathname);
const own = (await import(pathToFileURL(join(HERE, 'web/nexus-do/lexicon.js')))).default;
const ownData = (await import(pathToFileURL(join(HERE, 'web/nexus-do/lexicon_data.js')))).default;

let failed = 0;
const ok = (msg) => console.log(`  ✓ ${msg}`);
const bad = (msg) => { failed++; console.error(`  ✗ ${msg}`); };
const sha = (o) => createHash('sha256').update(JSON.stringify(o)).digest('hex');

// ── 黄金指纹(与 shuyu-lang tests/engine.test.mjs 同源同值)──
const GOLDEN = {
  capacity: 7_667_712_000,
  axes: { NC: 1040, NM: 180, NS: 80, NK: 64, NP: 8 },
  legacy20: '3cd2c7b3845dbbd02886c71f9e4f4e5bb46e5e512f3c2098f47092074b63a30b',
  core52: '6140778713efe218e79496347b8b3146fb56b6ebeb04b638474df4e651fa6f34',
  mani: 'a46d2a06a44f74e2f38eead710f3e3d2cddacc9403c90b323b36512eab9d149d',
  stat: 'f5122db790765b8e698374ab5a81f6e8b10ed954ef358dc1a09a44e743f32f38',
  scal: '3599bd52df338217739b1c0570909c329727c7572571badf01c08ddabda95069',
  phase: '08dba96e797c924eff89fdae3ce4dd285ce85701b30f6e09bd19af6c1458a69e',
  words: { 0: 'Ao-cor-is·qi', 2_949_120_000: 'Aur-cor-is·qi', 7_667_711_999: 'Glaxi-fncp-sta9-flxh·ying' },
};

function selfCheck() {
  console.log('① 引擎指纹自检(内置黄金值)');
  own.CAPACITY === GOLDEN.capacity ? ok(`容量 ${GOLDEN.capacity.toLocaleString('zh-CN')}`) : bad(`容量失配:${own.CAPACITY}`);
  if (!own.ROOTS) { bad('lexicon.js 缺 ROOTS 导出(副本过旧)'); return; }
  JSON.stringify(own.ROOTS.AXES) === JSON.stringify(GOLDEN.axes) ? ok('五轴轴长一致') : bad('五轴轴长失配');
  sha(own.ROOTS.CORE_BASE.slice(0, 20)) === GOLDEN.legacy20 ? ok('老 20 族核心词根未被改动') : bad('老 20 族核心词根被改动!历史编号会错位');
  sha(own.ROOTS.CORE_BASE) === GOLDEN.core52 ? ok('52 族核心词根与源头指纹一致') : bad('核心词根表与源头指纹失配');
  sha(own.ROOTS.MANI_BASE) === GOLDEN.mani ? ok('映轴一致') : bad('映轴被改动!');
  sha(own.ROOTS.STAT_BASE) === GOLDEN.stat ? ok('态轴一致') : bad('态轴被改动!');
  sha(own.ROOTS.SCAL_BASE) === GOLDEN.scal ? ok('标轴一致') : bad('标轴被改动!');
  sha(own.ROOTS.PHASE_BASE) === GOLDEN.phase ? ok('相轴一致') : bad('相轴被改动!');

  console.log('② 锚点解码 + 抽样往返');
  for (const [id, word] of Object.entries(GOLDEN.words)) {
    const w = own.decode(Number(id));
    w.词 === word ? ok(`id=${id} → ${word}`) : bad(`id=${id} 解出 ${w.词},应为 ${word}`);
  }
  let rt = 0;
  for (let k = 0; k < 2000; k++) {
    const id = Math.floor((k * (own.CAPACITY - 1)) / 1999);
    if (own.encode(own.decode(id).词) !== id) rt++;
  }
  rt === 0 ? ok('等距 2000 点双向寻址往返成立') : bad(`${rt} 点往返失败`);

  console.log('③ 能力数据包自洽性');
  let words = 0;
  for (const l of Object.keys(ownData.vocab || {})) for (const c of Object.keys(ownData.vocab[l])) words += ownData.vocab[l][c].length;
  ownData.meta.引擎容量 === own.CAPACITY ? ok(`meta.引擎容量 与引擎一致`) : bad(`meta.引擎容量 ${ownData.meta.引擎容量} 失配`);
  ownData.meta.能力总数 === words ? ok(`meta.能力总数 自洽:${words}`) : bad(`meta.能力总数 虚标:声称 ${ownData.meta.能力总数},实际 ${words}`);
}

async function fullCompare(srcRoot) {
  const src = (await import(pathToFileURL(join(srcRoot, 'lexicon.js')))).default;
  console.log('① 引擎容量');
  src.CAPACITY === own.CAPACITY ? ok(`容量一致:${own.CAPACITY.toLocaleString('zh-CN')}`) : bad(`容量失配:源头 ${src.CAPACITY} vs 本仓 ${own.CAPACITY}`);

  console.log('② 五轴词根表');
  if (!src.ROOTS || !own.ROOTS) { bad('一侧缺 ROOTS 导出,无法结构化比对'); }
  else {
    for (const axis of ['CORE_BASE', 'MANI_BASE', 'STAT_BASE', 'SCAL_BASE', 'PHASE_BASE']) {
      JSON.stringify(src.ROOTS[axis]) === JSON.stringify(own.ROOTS[axis])
        ? ok(`${axis} 一致(${own.ROOTS[axis].length} 条)`)
        : bad(`${axis} 失配`);
    }
  }

  console.log('③ 抽样解码(边界 + 等距 500 点)');
  const ids = [0, 1, 2_949_119_999, 2_949_120_000, own.CAPACITY - 1];
  for (let k = 0; k < 500; k++) ids.push(Math.floor((k * (own.CAPACITY - 1)) / 499));
  let diff = 0;
  for (const id of new Set(ids)) {
    const a = src.decode(id), b = own.decode(id);
    for (const f of ['词', '汉', '层', '义']) if (a[f] !== b[f]) { diff++; bad(`id=${id} 字段「${f}」失配`); }
    if (own.encode(a.词) !== id) { diff++; bad(`id=${id} 本仓反向寻址失败`); }
  }
  if (!diff) ok('抽样解码逐字段一致,双向寻址往返成立');

  console.log('④ 接口签名');
  for (const fn of ['decode', 'encode', 'matchWord', 'coinWord', 'coinFromCoord', 'autoCoin', 'coinFromState', 'loadCapabilities']) {
    typeof own[fn] === 'function' ? ok(`${fn} 存在`) : bad(`本仓缺接口 ${fn}`);
  }
  selfCheckDataOnly();
}

function selfCheckDataOnly() {
  console.log('⑤ 能力数据包自洽性');
  let words = 0;
  for (const l of Object.keys(ownData.vocab || {})) for (const c of Object.keys(ownData.vocab[l])) words += ownData.vocab[l][c].length;
  ownData.meta.引擎容量 === own.CAPACITY ? ok('meta.引擎容量 与引擎一致') : bad(`meta.引擎容量 ${ownData.meta.引擎容量} 失配`);
  ownData.meta.能力总数 === words ? ok(`meta.能力总数 自洽:${words}`) : bad(`meta.能力总数 虚标:声称 ${ownData.meta.能力总数},实际 ${words}`);
}

const argPath = process.argv[2];
const candidates = argPath ? [argPath] : [join(HERE, '../shuyu-lang'), join(HERE, '../Shuyu-Lang')];
const srcRoot = candidates.map((p) => resolve(p)).find((p) => existsSync(join(p, 'lexicon.js')));

if (srcRoot) {
  console.log(`同步校验:${srcRoot}(源头) ↔ ${HERE}(本仓消费方)\n`);
  await fullCompare(srcRoot);
} else {
  console.log(`未找到 shuyu-lang 源头仓,退化为内置指纹自检:${HERE}\n`);
  selfCheck();
}

console.log(failed ? `\n✗ 同步校验失败:${failed} 处失配,禁止发版` : '\n✓ 引擎同步校验全部通过');
process.exit(failed ? 1 : 0);
