// UI 双副本同步校验
// 用法: node tools/sync-ui.mjs [--check]   (纯校验;原 --fix 只服务工作台段,已随收口移除)
//
// 守护"同一份 UI 必须两处一致"的关系,防止改了一处忘了另一处、线上跑旧页面:
//   ① nexus-do 主界面:web/nexus-do/index.html ↔ 构建产物 nexus_do.mjs 内嵌副本
//      (页面在构建时以 JSON 字符串整体注入 Worker;改了 index.html 不重新构建,线上还是旧的)
//
// 2026-08-09 UI 收口(权哥拍板):主界面是唯一 UI,今后只做更新不再多副本。
// 原 ② studio 工作台双副本校验已随孤儿页归档一并移除(页面见 docs/archive/ui-收口-2026-08-09/)。
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
let failed = false;

// ── ① nexus-do 主界面:index.html ↔ 构建产物内嵌副本 ──
(() => {
  const htmlPath = path.join(ROOT, 'web/nexus-do/index.html');
  const builtPath = path.join(ROOT, 'web/nexus-do/nexus_do.mjs');
  if (!existsSync(builtPath)) {
    console.error('✗ [主界面] 找不到构建产物 nexus_do.mjs — 先跑: cd web/nexus-do && node build.mjs');
    failed = true; return;
  }
  const sourceHtml = readFileSync(htmlPath, 'utf8');
  const built = readFileSync(builtPath, 'utf8');
  if (built.includes('"__CHAT_HTML__"')) {
    console.error('✗ [主界面] 构建产物里还留着占位符,注入没生效 — 重跑: cd web/nexus-do && node build.mjs');
    failed = true; return;
  }
  // 与 build.mjs 完全同规则重建"预期嵌入页面":index.html + nexus-frontier.css 注入 </body> 前。
  // 之前直接拿原始 index.html 比对,永远对不上,检查形同虚设——必须复刻构建时的变换。
  const frontierPath = path.join(ROOT, 'web/nexus-do/nexus-frontier.css');
  const polishPath = path.join(ROOT, 'web/nexus-do/ui-polish.css');
  const frontier = existsSync(frontierPath) ? readFileSync(frontierPath, 'utf8') : '';
  const polish = existsSync(polishPath) ? readFileSync(polishPath, 'utf8') : '';
  const html = sourceHtml.replace(
    '</body>',
    () => `${frontier ? `<style id="nx-frontier-style">\n${frontier}\n</style>\n` : ''}${polish ? `<style id="nx-polish-style">\n${polish}\n</style>\n` : ''}</body>`,
  );
  if (built.includes(JSON.stringify(html))) {
    console.log(`✓ [主界面] nexus_do.mjs 内嵌页面与 index.html 一致 (${html.length} 字节)`);
  } else {
    console.error('✗ [主界面] 双副本失步: index.html 改过但没重新构建 — 重跑: cd web/nexus-do && node build.mjs');
    failed = true;
  }
})();

process.exit(failed ? 1 : 0);
