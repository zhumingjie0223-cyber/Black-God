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

// ── 畸形输入行为校验(硬) ──
// 2026-09 教训:上面只喂合法编号做往返,于是两侧「错误处理」怎么分叉都测不出来。
// 实测发现消费副本早已硬化 encode/decode,源头却还是老实现,分叉长期没人发现。
// 单射性是跨仓语义对齐的地基:同一个畸形词一侧判合法、另一侧判非法,语义就错位了。
const MALFORMED = [
  'Ao-cor-is-·qi',        // 显式空标段:会和 3 段词形撞同一个编号
  'Ao-cor-is·qi·qi',      // 多写一个相位分隔符
  'Ao-cor-is-gal-p·qi',   // 5 段,超出「核-映-态-标」上限
  'Ao-cor·qi',            // 只有 2 段
  'Ao-cor-is-gal',        // 缺相位
  '-cor-is·qi',           // 核轴为空
  'Ao-cor-is-XX·qi',      // 标轴词根不存在
  '', '不是词', 'Zzz-cor-is·qi',
];
let badDiverged = 0, badAccepted = 0;
for (const w of MALFORMED) {
  const ra = A.encode(w), rb = B.encode(w);
  if (ra !== rb) { if (badDiverged < 5) fail(`畸形词「${w}」判定分叉: 本仓=${ra} 对方=${rb}`); badDiverged++; }
  else if (ra !== -1) { if (badAccepted < 5) fail(`畸形词「${w}」被两侧同时误判为合法编号 ${ra}(破坏 encode 单射)`); badAccepted++; }
}
if (!badDiverged && !badAccepted) ok(`畸形输入判定一致: ${MALFORMED.length} 个非法词形两侧均正确拒绝`);

// decode 的入参守卫也必须同步:非整数要抛错,不能一侧抛一侧返回垃圾词
let guardDiverged = 0;
for (const bad of [NaN, 1.5, undefined, null, '100', true, -1, cap]) {
  const probe = (ENG) => { try { ENG.decode(bad); return 'ACCEPTED'; } catch { return 'THREW'; } };
  const ra = probe(A), rb = probe(B);
  if (ra !== rb) { fail(`decode(${String(bad)}) 守卫分叉: 本仓=${ra} 对方=${rb}`); guardDiverged++; }
  else if (ra === 'ACCEPTED') { fail(`decode(${String(bad)}) 两侧都放行了非法入参`); guardDiverged++; }
}
if (!guardDiverged) ok('decode 入参守卫一致: 非整数与越界值两侧均拒绝');

// ── v4.1 新能力校验(硬,双方都导出该函数时才比;单方缺失说明副本没同步,也算硬失败) ──
// encodeHan / autoCoin / compose / search 是 2026-09 长出来的能力,消费副本落后一版就会
// 出现"源头能汉译反查、副本不能"的裂缝;这里逐一比对,不再只盯 decode/encode。
const NEW_API = ['encodeHan', 'search', 'compose', 'autoCoin', 'coinFromCoord'];
const missingA = NEW_API.filter(f => typeof A[f] !== 'function');
const missingB = NEW_API.filter(f => typeof B[f] !== 'function');
if (missingA.length || missingB.length) {
  fail(`v4.1 接口缺失: 本仓缺[${missingA.join('、')}] / 对方缺[${missingB.join('、')}](副本未同步)`);
} else {
  let apiDiverged = 0;
  for (const id of ids) {
    const a = A.decode(id), b = B.decode(id);
    if (A.encodeHan(a.汉) !== id || B.encodeHan(b.汉) !== id) { if (apiDiverged < 5) fail(`编号 ${id} 汉译往返失败: 本仓=${A.encodeHan(a.汉)} 对方=${B.encodeHan(b.汉)}`); apiDiverged++; }
    if (JSON.stringify(a.坐标) !== JSON.stringify(b.坐标) || JSON.stringify(a.根) !== JSON.stringify(b.根)) { if (apiDiverged < 5) fail(`编号 ${id} 根/坐标字段分叉`); apiDiverged++; }
  }
  for (const seed of ['神枢', '阿权', '', '0', '赵思涵|情感', ...Array.from({ length: 50 }, (_, i) => '种子' + i)]) {
    if (A.autoCoin(seed).id !== B.autoCoin(seed).id) { if (apiDiverged < 5) fail(`autoCoin(「${seed}」) 分叉: 本仓=${A.autoCoin(seed).id} 对方=${B.autoCoin(seed).id}`); apiDiverged++; }
  }
  for (const spec of [{ 核: '毁灭', 映: '光', 态: '爆', 标: '溯', 相: '起' }, { c: 120, m: 24, s: 50, k: 32, p: 0 }, { 核: 'Aoa' }, {}, { 标: '无极', 态: '爆九' }]) {
    if (A.compose(spec).id !== B.compose(spec).id) { if (apiDiverged < 5) fail(`compose(${JSON.stringify(spec)}) 分叉`); apiDiverged++; }
  }
  for (const kw of ['毁灭', '熵', 'gal', '光', '起', '无极', '']) {
    if (JSON.stringify(A.search(kw)) !== JSON.stringify(B.search(kw))) { if (apiDiverged < 5) fail(`search(「${kw}」) 分叉`); apiDiverged++; }
  }
  for (const bad of ['奥形凝起起', '奥形凝甲起', '甲形凝起', '', '不是词']) {
    if (A.encodeHan(bad) !== -1 || B.encodeHan(bad) !== -1) { if (apiDiverged < 5) fail(`畸形汉译「${bad}」被放行: 本仓=${A.encodeHan(bad)} 对方=${B.encodeHan(bad)}`); apiDiverged++; }
  }
  if (!apiDiverged) ok(`v4.1 接口一致: encodeHan 往返 ${ids.size} 个编号 / autoCoin 55 种子 / compose 5 规格 / search 7 关键词 两侧全同`);
  else fail(`v4.1 接口共 ${apiDiverged} 处分叉`);
}

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
