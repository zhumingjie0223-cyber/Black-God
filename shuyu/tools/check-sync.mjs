// 同步校验 — 枢语源头引擎(本目录 shuyu/) ↔ Black God 消费副本(web/nexus-do)
// 两仓已合一:本目录即 Black-God/shuyu/,消费副本在上一级 web/nexus-do/,不带参数自动找到。
// 用法: node tools/check-sync.mjs [对方路径] [--strict]
//   引擎层(词根表/容量/编解码行为)不一致 → 硬失败(退出码 1)
//   数据层(词库/情绪表/编号表)分叉      → 警告报告(--strict 时也算失败)
import { existsSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const HERE = path.dirname(path.dirname(fileURLToPath(import.meta.url))); // 本仓根目录
const args = process.argv.slice(2).filter(a => a !== '--strict');
const strict = process.argv.includes('--strict');

// 定位一个仓库里的引擎与数据文件(源头仓在根目录，Black God 在 web/nexus-do/)
function locate(repoRoot) {
  for (const sub of ['web/nexus-do', '.']) {
    const eng = path.join(repoRoot, sub, 'lexicon.js');
    if (existsSync(eng)) return { engine: eng, data: path.join(repoRoot, sub, 'lexicon_data.js') };
  }
  return null;
}

// 对方路径:显式参数优先;否则先找合仓后的宿主根(本目录 shuyu/ 的上一级),再猜同级目录(兼容旧布局)
let peerRoot = args[0];
if (!peerRoot) {
  const parent = path.dirname(HERE);   // 合仓后:HERE=Black-God/shuyu,parent=Black-God 根(内含 web/nexus-do)
  const cands = [
    parent,
    ...['shuyu-lang', 'black-god', 'Black-God', 'BLACK-GOD'].map(s => path.join(parent, s)),
  ];
  peerRoot = cands.find(p => p !== HERE && existsSync(p) && locate(p));
}
if (!peerRoot || !locate(peerRoot)) {
  console.error('✗ 找不到对方仓库,请显式传路径: node tools/check-sync.mjs <对方仓路径>');
  process.exit(1);
}

const self = locate(HERE), peer = locate(peerRoot);
console.log(`本仓引擎: ${path.relative(process.cwd(), self.engine)}`);
console.log(`对方引擎: ${path.relative(process.cwd(), peer.engine)}\n`);

const A = (await import(pathToFileURL(self.engine))).default;
const B = (await import(pathToFileURL(peer.engine))).default;

let engineFail = 0, warns = 0;
const fail = m => { console.error('✗ ' + m); engineFail++; };
const warn = m => { console.warn('⚠ ' + m); warns++; };
const ok = m => console.log('✓ ' + m);

// ── 引擎层校验(硬) ──
if (A.CAPACITY !== B.CAPACITY) fail(`容量不一致: 本仓 ${A.CAPACITY} vs 对方 ${B.CAPACITY}`);
else ok(`容量一致: ${A.CAPACITY.toLocaleString()}`);

// 采样覆盖全部核心族 + 确定性随机点 + 边界
const cap = Math.min(A.CAPACITY, B.CAPACITY);
const ids = new Set([0, 1, cap - 1, 2949119999, 2949120000]);
const NM = 180, NS = 80, NK = 64, NP = 8, NC = cap / (NM * NS * NK * NP);
for (let c = 0; c < NC; c += 1) ids.add(((((c * NM) + c % NM) * NS + c % NS) * NK + c % NK) * NP + c % NP);
let x = 20260712n;
for (let i = 0; i < 500; i++) { x = (6364136223846793005n * x + 1442695040888963407n) % (1n << 64n); ids.add(Number(x % BigInt(cap))); }

let diverged = 0;
for (const id of ids) {
  const a = A.decode(id), b = B.decode(id);
  for (const f of ['词', '汉', '层', '义']) {
    if (a[f] !== b[f]) { if (diverged < 5) fail(`编号 ${id} 字段「${f}」分叉: 本仓=${a[f]} 对方=${b[f]}`); diverged++; break; }
  }
  if (A.encode(a.词) !== id || B.encode(b.词) !== id) { fail(`编号 ${id} 往返失败`); }
}
if (!diverged) ok(`编解码行为一致: 采样 ${ids.size} 个编号(覆盖全部 ${NC} 个核心行)全通过`);
else fail(`共 ${diverged} 个采样编号分叉`);

// ── 数据层校验(软) ──
const DA = (await import(pathToFileURL(self.data))).default;
const DB = (await import(pathToFileURL(peer.data))).default;

for (const [name, D, ENG] of [['本仓', DA, A], ['对方', DB, B]]) {
  const badIds = Object.entries(D.word_ids).filter(([, id]) => !Number.isInteger(id) || id < 0 || id >= ENG.CAPACITY);
  if (badIds.length) fail(`${name}词库有 ${badIds.length} 个编号越界,如: ${badIds.slice(0, 3).map(([w, i]) => `${w}=${i}`).join(', ')}`);
  // 空串/纯空白键是脱敏/迁移残留的垃圾词条(如把人格词清成空串却没删条目),硬失败
  const emptyKeys = Object.keys(D.word_ids).filter(w => w.trim() === '');
  if (emptyKeys.length) fail(`${name}词库有 ${emptyKeys.length} 个空/纯空白词条(编号=${emptyKeys.map(w => D.word_ids[w]).join(', ')}),应整条删除而非留空键`);
}

const famA = Object.keys(DA.vocab), famB = Object.keys(DB.vocab);
const onlyA = famA.filter(k => !DB.vocab[k]), onlyB = famB.filter(k => !DA.vocab[k]);
if (onlyA.length || onlyB.length)
  warn(`词族分叉: 仅本仓有 ${onlyA.length} 族[${onlyA.join('、')}] / 仅对方有 ${onlyB.length} 族[${onlyB.join('、')}]`);
else ok(`词族一致: ${famA.length} 族`);

const emoA = (DA.emotions || []).map(e => e.触发), emoB = (DB.emotions || []).map(e => e.触发);
if (JSON.stringify(emoA) !== JSON.stringify(emoB))
  warn(`情绪表分叉: 本仓 ${emoA.length} 条 vs 对方 ${emoB.length} 条(属产品定制层,允许各自演化)`);
else ok(`情绪表一致: ${emoA.length} 条`);

const wa = Object.keys(DA.word_ids), wb = Object.keys(DB.word_ids);
const commonDiff = wa.filter(w => w in DB.word_ids && DA.word_ids[w] !== DB.word_ids[w]);
const idOnlyA = wa.filter(w => !(w in DB.word_ids)).length, idOnlyB = wb.filter(w => !(w in DA.word_ids)).length;
if (commonDiff.length)
  fail(`同一能力词映射到不同编号(会导致跨仓语义错位) ${commonDiff.length} 处,如: ${commonDiff.slice(0, 3).join('、')}`);
if (idOnlyA || idOnlyB) warn(`编号表词条分叉: 仅本仓 ${idOnlyA} 条 / 仅对方 ${idOnlyB} 条`);
if (!commonDiff.length && !idOnlyA && !idOnlyB) ok(`编号表一致: ${wa.length} 条`);

// ── 结论 ──
console.log('');
if (engineFail) { console.error(`✗ 同步校验失败: ${engineFail} 个硬性问题${warns ? ` + ${warns} 个警告` : ''}`); process.exit(1); }
if (warns && strict) { console.error(`✗ 严格模式: ${warns} 个数据层分叉视为失败`); process.exit(1); }
console.log(warns ? `✓ 引擎层完全同步(数据层有 ${warns} 处分叉警告,详见上方)` : '✓ 双仓完全同步');
