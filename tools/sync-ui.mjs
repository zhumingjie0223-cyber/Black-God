// UI 双副本同步校验 — web/nexus-do/index.html ↔ 构建产物 nexus_do.mjs 内嵌副本
// 用法: node tools/sync-ui.mjs --check   (无参数等同 --check)
// 页面是构建时以 JSON 字符串整体注入 Worker 的;改了 index.html 不重新构建,
// 线上跑的还是旧页面。本工具就查这一件事:构建产物里的副本是否等于当前 index.html。
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const htmlPath = path.join(ROOT, 'web/nexus-do/index.html');
const builtPath = path.join(ROOT, 'web/nexus-do/nexus_do.mjs');

if (!existsSync(builtPath)) {
  console.error('✗ 找不到构建产物 nexus_do.mjs — 先跑: cd web/nexus-do && node build.mjs');
  process.exit(1);
}

const html = readFileSync(htmlPath, 'utf8');
const built = readFileSync(builtPath, 'utf8');

if (built.includes('"__CHAT_HTML__"')) {
  console.error('✗ 构建产物里还留着占位符,注入没生效 — 重跑: cd web/nexus-do && node build.mjs');
  process.exit(1);
}
if (built.includes(JSON.stringify(html))) {
  console.log(`✓ 双副本同步: nexus_do.mjs 内嵌页面与 index.html 一致 (${html.length} 字节)`);
} else {
  console.error('✗ 双副本失步: index.html 改过但没重新构建 — 重跑: cd web/nexus-do && node build.mjs');
  process.exit(1);
}
