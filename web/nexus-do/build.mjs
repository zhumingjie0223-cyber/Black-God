// 构建：把 index.html 安全注入 nexus_do.core.mjs → 生成 nexus_do.mjs
// UI 以 JSON 字符串常量嵌入，杜绝模板字符串截断/转义问题。
// 用法：node build.mjs
import { readFileSync, writeFileSync, statSync } from 'node:fs';

const html = readFileSync(new URL('./index.html', import.meta.url), 'utf8');
let core = readFileSync(new URL('./nexus_do.core.mjs', import.meta.url), 'utf8');
const marker = '"__CHAT_HTML__"';
if (!core.includes(marker)) throw new Error('marker "__CHAT_HTML__" not found in core');
core = core.replace(marker, JSON.stringify(html));
writeFileSync(new URL('./nexus_do.mjs', import.meta.url), core);
console.log('✓ built nexus_do.mjs', statSync(new URL('./nexus_do.mjs', import.meta.url)).size, 'bytes · html', html.length, 'bytes');
