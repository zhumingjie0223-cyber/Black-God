// UI 双副本同步校验
// 用法: node tools/sync-ui.mjs [--check|--fix]   (无参数等同 --check)
//
// 守护两组"同一份 UI 必须两处一致"的关系,防止改了一处忘了另一处、线上跑旧页面:
//   ① nexus-do 主界面:web/nexus-do/index.html ↔ 构建产物 nexus_do.mjs 内嵌副本
//      (页面在构建时以 JSON 字符串整体注入 Worker;改了 index.html 不重新构建,线上还是旧的)
//   ② studio 工作台:web/nexus-studio/public/index.html(线上工作台权威源)↔ web/nexus-do/studio.html
//      (方案①下 nexus-studio〔CF worker〕是工作台权威;nexus-do/studio.html 是随静态发布的镜像副本,
//       两份必须逐字节一致,否则会分叉。--fix 时以权威源覆盖镜像副本。)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const MODE = process.argv.includes('--fix') ? 'fix' : 'check';
let failed = false;

// ── ① nexus-do 主界面:index.html ↔ 构建产物内嵌副本 ──
(() => {
  const htmlPath = path.join(ROOT, 'web/nexus-do/index.html');
  const builtPath = path.join(ROOT, 'web/nexus-do/nexus_do.mjs');
  if (!existsSync(builtPath)) {
    console.error('✗ [主界面] 找不到构建产物 nexus_do.mjs — 先跑: cd web/nexus-do && node build.mjs');
    failed = true; return;
  }
  const html = readFileSync(htmlPath, 'utf8');
  const built = readFileSync(builtPath, 'utf8');
  if (built.includes('"__CHAT_HTML__"')) {
    console.error('✗ [主界面] 构建产物里还留着占位符,注入没生效 — 重跑: cd web/nexus-do && node build.mjs');
    failed = true; return;
  }
  if (built.includes(JSON.stringify(html))) {
    console.log(`✓ [主界面] nexus_do.mjs 内嵌页面与 index.html 一致 (${html.length} 字节)`);
  } else {
    console.error('✗ [主界面] 双副本失步: index.html 改过但没重新构建 — 重跑: cd web/nexus-do && node build.mjs');
    failed = true;
  }
})();

// ── ② studio 工作台:nexus-studio 权威源 ↔ nexus-do 镜像副本 ──
(() => {
  const authPath = path.join(ROOT, 'web/nexus-studio/public/index.html'); // 权威源(线上工作台)
  const mirrorPath = path.join(ROOT, 'web/nexus-do/studio.html');         // 镜像副本(随静态发布)
  if (!existsSync(authPath) || !existsSync(mirrorPath)) {
    console.log('· [工作台] 缺少 studio 副本之一,跳过校验(部署边界清理后可能只剩权威源)');
    return;
  }
  const auth = readFileSync(authPath, 'utf8');
  const mirror = readFileSync(mirrorPath, 'utf8');
  if (auth === mirror) {
    console.log(`✓ [工作台] studio 双副本一致 (${auth.length} 字节)`);
  } else if (MODE === 'fix') {
    writeFileSync(mirrorPath, auth);
    console.log(`✓ [工作台] 已以权威源覆盖镜像副本 web/nexus-do/studio.html (${auth.length} 字节)`);
  } else {
    console.error('✗ [工作台] studio 双副本失步: web/nexus-studio/public/index.html 与 web/nexus-do/studio.html 不一致');
    console.error('  以 nexus-studio 为权威源,跑 `node tools/sync-ui.mjs --fix` 覆盖镜像副本');
    failed = true;
  }
})();

process.exit(failed ? 1 : 0);
