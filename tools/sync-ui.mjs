#!/usr/bin/env node
// UI 单一事实源同步 — 设计系统 V3
//
// 1) web/design/tokens.css（源）→ web/nexus-studio/public/design/tokens.css（副本，
//    nexus-studio Worker 只发布 public/ 内的静态资源）
// 2) web/nexus-do/studio.html（源）→ web/nexus-studio/public/index.html（镜像，
//    历史上两份手工拷贝曾经字节级相同，本脚本把镜像关系固化）
//
// 用法：node tools/sync-ui.mjs          # 执行同步
//       node tools/sync-ui.mjs --check  # 只校验，不一致时退出码 1（CI 用）
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const checkOnly = process.argv.includes('--check');

const PAIRS = [
  ['web/design/tokens.css', 'web/nexus-studio/public/design/tokens.css'],
  ['web/nexus-do/studio.html', 'web/nexus-studio/public/index.html'],
];

let dirty = 0;
for (const [srcRel, dstRel] of PAIRS) {
  const src = path.join(ROOT, srcRel);
  const dst = path.join(ROOT, dstRel);
  const srcData = readFileSync(src, 'utf8');
  const dstData = existsSync(dst) ? readFileSync(dst, 'utf8') : null;
  if (srcData === dstData) {
    console.log(`✓ 已同步 ${dstRel}`);
    continue;
  }
  dirty++;
  if (checkOnly) {
    console.error(`✗ 不同步 ${srcRel} → ${dstRel}（运行 node tools/sync-ui.mjs 修复）`);
  } else {
    mkdirSync(path.dirname(dst), { recursive: true });
    writeFileSync(dst, srcData);
    console.log(`✎ 已写入 ${dstRel}`);
  }
}

if (checkOnly && dirty > 0) process.exit(1);
console.log(dirty === 0 ? '全部同步 ✓' : `同步完成（${dirty} 处更新）`);
