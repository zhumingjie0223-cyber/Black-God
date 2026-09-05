// 构建：把 index.html + 前沿增强层安全注入 nexus_do.core.mjs → 生成 nexus_do.mjs
// UI 以 JSON 字符串常量嵌入，杜绝模板字符串截断/转义问题。
// 用法：node build.mjs
import { readFileSync, writeFileSync, statSync } from 'node:fs';

const sourceHtml = readFileSync(new URL('./index.html', import.meta.url), 'utf8');
const frontier = readFileSync(new URL('./nexus-frontier.css', import.meta.url), 'utf8');
const polish = readFileSync(new URL('./ui-polish.css', import.meta.url), 'utf8');
if (!sourceHtml.includes('</body>')) throw new Error('index.html missing closing </body>');
// 放到 body 尾部：优先级在两段既有 style 之后，不需要改原有 UI 规则。
// ui-polish 最后注入，确保覆盖 frontier 和所有既有规则。
const html = sourceHtml.replace(
  '</body>',
  () => `<style id="nx-frontier-style">\n${frontier}\n</style>\n<style id="nx-polish-style">\n${polish}\n</style>\n</body>`,
);
let core = readFileSync(new URL('./nexus_do.core.mjs', import.meta.url), 'utf8');
const marker = '"__CHAT_HTML__"';
if (!core.includes(marker)) throw new Error('marker "__CHAT_HTML__" not found in core');
// 必须用函数式替换:直接传字符串时 replace 会把 $$/$& 等序列当特殊替换符吞掉,
// 页面里的 `const $$ = ...` 会被毁成重复声明 `const $`,整页脚本语法错误。
core = core.replace(marker, () => JSON.stringify(html));
writeFileSync(new URL('./nexus_do.mjs', import.meta.url), core);
// 同步产出完整 HTML 供本地 Python server 直接托管（含 frontier + ui-polish）
writeFileSync(new URL('./index.built.html', import.meta.url), html);
console.log('✓ built nexus_do.mjs', statSync(new URL('./nexus_do.mjs', import.meta.url)).size, 'bytes · html', html.length, 'bytes · index.built.html');
