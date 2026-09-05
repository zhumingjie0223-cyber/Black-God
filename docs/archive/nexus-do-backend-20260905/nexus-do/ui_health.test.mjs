// 神枢 · 页面健康守门（纯 Node，无需浏览器、无新依赖）
//
// 立此关卡的由来：2026-08-02 NavCore v3 合入时带进三个 JS 语法错误，
// 主脚本块整块解析失败 → 所有事件绑不上、登录门弹不出来，界面看得见点不动，
// 而 selftest 与全部单测**照样全绿**（它们从不加载页面），于是静默死了 15 天。
// 这里补上页面层的三道检查，让同类事故当场暴露：
//   ① 每个内联 <script> 必须语法正确
//   ② 顶层 let/const 跨脚本块不得重名（经典 script 的顶层词法作用域是共享的）
//   ③ HTML 的 onclick 里调到的函数必须真的存在（防「按钮是死的」）
//
// 用法：node ui_health.test.mjs
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('./index.html', import.meta.url), 'utf8');
let pass = 0, fail = 0;
const ok = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('✓', name); }
  else { fail++; console.error('✗', name, detail ? '\n   ' + detail : ''); }
};

// 抽出所有内联 <script>（带 src 的外链不管）
const blocks = [];
for (const m of html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)) {
  blocks.push({ code: m[1], line: html.slice(0, m.index).split('\n').length });
}
ok(`找到内联脚本块（${blocks.length} 个）`, blocks.length > 0);

// ① 逐块语法检查：任何一块炸了，整块脚本在浏览器里就不执行
for (const b of blocks) {
  let err = null;
  try { new vm.Script(b.code); } catch (e) { err = e.message; }
  ok(`脚本块（起始行 ${b.line}）语法正确`, !err,
    err ? `${err}\n   → 这块脚本在浏览器里整块不会执行，页面会「看得见点不动」` : '');
}

// ② 顶层 let/const 跨块重名检查
// 经典 <script> 的顶层 let/const 进的是共享的全局词法环境，两块各声明一次同名变量
// 照样报 “Identifier 'x' has already been declared”，而单块语法检查发现不了。
{
  const seen = new Map();
  const dups = [];
  for (const b of blocks) {
    const lines = b.code.split('\n');
    for (let i = 0; i < lines.length; i++) {
      // 顶层 = 行首无缩进（本页代码风格：嵌套一律缩进）
      const m = /^(?:let|const)\s+([A-Za-z_$][\w$]*)/.exec(lines[i]);
      if (!m) continue;
      const name = m[1], at = `第 ${b.line + i} 行`;
      if (seen.has(name)) dups.push(`${name}（${seen.get(name)} 与 ${at}）`);
      else seen.set(name, at);
    }
  }
  ok('顶层 let/const 无重名', dups.length === 0,
    dups.length ? `重复声明：${dups.join('、')}\n   → 会让后一块脚本整块解析失败` : '');
}

// ③ onclick 里调用的函数必须真的存在（按钮不能是死的）
{
  // 收集定义：function f(){} / const f = / let f = / var f = / window.f =
  const defined = new Set();
  for (const m of html.matchAll(/function\s+([A-Za-z_$][\w$]*)\s*\(/g)) defined.add(m[1]);
  for (const m of html.matchAll(/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/g)) defined.add(m[1]);
  for (const m of html.matchAll(/window\.([A-Za-z_$][\w$]*)\s*=/g)) defined.add(m[1]);

  // 浏览器内置 / 全局对象，不算缺失
  const builtin = new Set(['alert', 'confirm', 'prompt', 'open', 'close', 'print', 'fetch',
    'setTimeout', 'setInterval', 'requestAnimationFrame', 'encodeURIComponent', 'decodeURIComponent',
    'parseInt', 'parseFloat', 'String', 'Number', 'Boolean', 'Array', 'Object', 'JSON', 'Math', 'Date',
    // CSS 函数：onclick 里常写 style.background='var(--x)' 之类，不是 JS 调用，别误报
    'var', 'url', 'calc', 'rgb', 'rgba', 'hsl', 'hsla', 'linear-gradient']);

  const missing = new Set();
  for (const m of html.matchAll(/on(?:click|change|input|submit)="([^"]*)"/g)) {
    for (const c of m[1].matchAll(/(?:^|[^.\w$])([A-Za-z_$][\w$]*)\s*\(/g)) {
      const name = c[1];
      if (!defined.has(name) && !builtin.has(name)) missing.add(name);
    }
  }
  ok('onclick 调用的函数都已定义', missing.size === 0,
    missing.size ? `未定义：${[...missing].join('、')}\n   → 这些按钮点了会报 ReferenceError，等于死按钮` : '');
}

// ④ 主内容容器必须真的可见：本页三个页面装在 #pager > #pages 里，
// 若有 CSS 规则把它们 display:none 掉（NavCore v3 就干过，且新容器 .tab-panels 从没建进 HTML），
// 整个应用主体对所有人永久不可见——顶栏底栏还在，中间一片黑，极难察觉。
{
  // 先剥掉注释再查：说明性注释里往往会引用这条规则的原文（本文件的修复注释就是），
  // 不剥会把注释当成真规则误报。
  const htmlNoComments = html.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');
  const hideRule = /\.(?:pager|pages)\s*(?:,[^{]*)?\{[^}]*display\s*:\s*none/.test(htmlNoComments);
  ok('主内容容器 #pager/#pages 未被 CSS 隐藏', !hideRule,
    hideRule ? '发现把 .pager/.pages 设为 display:none 的规则\n   → 三个页面会整体不可见，页面只剩顶栏和底栏' : '');

  // 新容器若只有 CSS/JS 而没有 HTML 元素，说明迁移做了一半，正是上面那条规则的由来
  const cssHasTabPanels = /\.tab-panels\s*[{,]/.test(htmlNoComments);
  const domHasTabPanels = /class="[^"]*\btab-panels\b/.test(htmlNoComments);
  ok('不存在「只有样式没有元素」的半拉子容器', !(cssHasTabPanels && !domHasTabPanels),
    (cssHasTabPanels && !domHasTabPanels)
      ? '.tab-panels 有 CSS 却没有对应 HTML 元素 —— 迁移只做了一半\n   → 要么补齐 HTML，要么把这套样式/脚本删干净，别留半拉子' : '');
}

// ⑤ 顶层 getElementById 不得取用「还没出现的元素」
// 经典 <script> 是边解析边执行：写在第 3984 行的 const x=getElementById('foo')，
// 若 foo 在第 6912 行才出现，取到的永远是 null，且不报任何错。今天已被咬两次
// （#sheetRoot → 所有设置面板静默打不开，表现为"整个界面点不动"；fmtTs 同类顺序问题）。
{
  const bad = [];
  for (const b of blocks) {
    const lines = b.code.split('\n');
    for (let i = 0; i < lines.length; i++) {
      // 只查顶层（行首无缩进）的 const/let/var 赋值，函数体内的是运行时取用，不受此限
      // 覆盖三种写法：getElementById('x') / $('#x') / querySelector('#x')
      const m = /^(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:document\.getElementById\(\s*['"]([\w-]+)['"]|\$\(\s*['"]#([\w-]+)['"]|document\.querySelector\(\s*['"]#([\w-]+)['"])/.exec(lines[i]);
      if (!m) continue;
      // 已写兜底的（如 `$('#x') || 现场创建`）不算隐患，那正是推荐写法
      if (lines[i].includes('||')) continue;
      const elemId = m[1] || m[2] || m[3];
      const idPos = html.indexOf(`id="${elemId}"`);
      const linePos = html.split('\n').slice(0, b.line + i - 1).join('\n').length;
      if (idPos === -1) bad.push(`${elemId}（页面里没有这个元素）`);
      else if (idPos > linePos) bad.push(`${elemId}（元素在第 ${html.slice(0, idPos).split('\n').length} 行，取用却在第 ${b.line + i} 行）`);
    }
  }
  ok('顶层 getElementById 取用的元素都已先出现', bad.length === 0,
    bad.length ? `取到的永远是 null 且不报错：${bad.join('、')}\n   → 改成用时再取（惰性），或把元素挪到脚本之前` : '');
}

// ⑥ 全局同名冲突：顶层 function f(){} 与 window.f = ... 撞名
// 顶层函数声明会挂到 window 且被提升，之后的 window.f=… 会把它整个覆盖；
// 调用方写裸标识符 f() 时拿到的是后者。今天被咬两次：
//   toast（被 <div id="toast"> 的具名访问顶掉 → 提示全站失效/崩栈）
//   applyTheme（深浅色版被调色板版覆盖 → 外观开关永远切不动）
{
  const fnDecl = new Set();
  for (const b of blocks) for (const m of b.code.matchAll(/^function\s+([A-Za-z_$][\w$]*)\s*\(/gm)) fnDecl.add(m[1]);
  // 只揪「window.f = window.f || …」这种幂等写法：它的本意是"别重复定义"，
  // 却因同名函数声明被提升而永远短路，真实现从此永不生效（toast / esc 都栽在这）。
  // 而「const _fOrig = window.f; window.f = 包装…」是有意的功能增强，属正当写法，放行。
  const idempotent = new Set();
  for (const b of blocks) for (const m of b.code.matchAll(/^window\.([A-Za-z_$][\w$]*)\s*=\s*window\.\1\s*\|\|/gm)) idempotent.add(m[1]);
  const clash = [...fnDecl].filter(n => idempotent.has(n));

  // 元素 id 也会被浏览器"具名访问"挂到 window 上，与同名函数/变量互相顶掉
  // 同样先剥注释：修复说明里常引用旧的 id="x" 原文，不剥会误报
  const htmlNC = html.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');
  const elemIds = new Set([...htmlNC.matchAll(/\bid="([\w$]+)"/g)].map(m => m[1]));
  const idClash = [...fnDecl].filter(n => elemIds.has(n)).concat([...idempotent].filter(n => elemIds.has(n)));

  ok('幂等赋值 window.f=window.f||… 未被同名函数声明架空', clash.length === 0,
    clash.length ? `同名：${clash.join('、')}\n   → 后者会覆盖前者，调用方拿到的可能不是你以为的那个` : '');
  ok('函数名不与元素 id 撞车', idClash.length === 0,
    idClash.length ? `撞名：${[...new Set(idClash)].join('、')}\n   → 元素会被挂成 window.<id>，把同名函数顶掉` : '');
}

// ⑦ 诚实故障态不得被改回"静默假在线"
// 由来：2026-08-19 收口 P1「前端别再静默假装在线」。后端挂了时 getSoul/getInner/talk
// 会 catch→Demo 兜底,若状态灯仍显"在线/演示",主人分不清"我没配后端"和"我的后端挂了"。
// 修法:_fetch 集中记 Nexus.fault(抛错=offline连不上 / 5xx=error后端异常),setLive 里
// 故障态压过演示/在线。这三处任一被删,静默假在线就会复活,故在此结构性锁死。
{
  const htmlNC = html.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');
  ok('Nexus 连接层声明了 fault 故障字段',
    /\bfault\s*:\s*null\b/.test(htmlNC),
    'Nexus 里找不到 fault:null —— 故障态跟踪被移除,后端挂了会静默假装在线');
  ok('_fetch 在 fetch 抛错时把 fault 记为 offline',
    /catch\s*\([^)]*\)\s*\{[^}]*fault\s*=\s*['"]offline['"]/.test(htmlNC),
    '_fetch 的 catch 未记 fault=offline —— 网络连不上时状态灯不会亮故障');
  ok('setLive 以 Nexus.fault 判定故障态(压过演示/在线)',
    /function\s+setLive[\s\S]{0,600}Nexus\.fault/.test(htmlNC),
    'setLive 未读 Nexus.fault —— 故障时会被 Demo 兜底撑成"在线",糊弄主人');
  ok('故障态点样式 .dot.err / .dot.warn 都在',
    /\.dot\.err\s*\{/.test(htmlNC) && /\.dot\.warn\s*\{/.test(htmlNC),
    '缺 .dot.err / .dot.warn 样式 —— 故障态点无颜色,主人看不见真实故障');
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
