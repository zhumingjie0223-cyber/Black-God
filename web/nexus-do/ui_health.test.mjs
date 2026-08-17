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

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
