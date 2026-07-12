#!/usr/bin/env node
// UI 双副本同步校验/重建
// 背景:web/nexus-do/index.html 是页面源码,构建时以 JSON 字符串整体注入
//      nexus_do.core.mjs 的 "__CHAT_HTML__" 占位符生成 nexus_do.mjs(部署副本)。
//      两个副本(源码 ↔ 部署产物)一旦漂移,线上跑的就不是你改的页面。
// 用法:
//   node tools/sync-ui.mjs --check   只校验,漂移则退出码 1(CI 门禁)
//   node tools/sync-ui.mjs           直接重建 nexus_do.mjs(等价 build.mjs)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const HERE = resolve(new URL('..', import.meta.url).pathname);
const DIR = join(HERE, 'web/nexus-do');
const MARKER = '"__CHAT_HTML__"';

const html = readFileSync(join(DIR, 'index.html'), 'utf8');
const core = readFileSync(join(DIR, 'nexus_do.core.mjs'), 'utf8');

if (!core.includes(MARKER)) {
  console.error(`✗ nexus_do.core.mjs 缺占位符 ${MARKER},构建链路已被破坏`);
  process.exit(1);
}

const expected = core.replace(MARKER, JSON.stringify(html));
const builtPath = join(DIR, 'nexus_do.mjs');

if (process.argv.includes('--check')) {
  if (!existsSync(builtPath)) {
    console.error('✗ 部署副本 nexus_do.mjs 不存在,请先 node build.mjs');
    process.exit(1);
  }
  const actual = readFileSync(builtPath, 'utf8');
  if (actual === expected) {
    console.log(`✓ UI 双副本同步:index.html(${html.length} 字节) 与 nexus_do.mjs 注入内容一致`);
    process.exit(0);
  }
  const htmlInSync = actual.includes(JSON.stringify(html));
  console.error('✗ UI 双副本漂移:nexus_do.mjs 不是当前 index.html + nexus_do.core.mjs 的构建产物');
  console.error(htmlInSync
    ? '  (页面注入一致,但 nexus_do.core.mjs 逻辑有改动未重建)'
    : '  (index.html 改动后未重建,线上跑的还是旧页面)');
  console.error('  修复:cd web/nexus-do && node build.mjs   或   node tools/sync-ui.mjs');
  process.exit(1);
}

writeFileSync(builtPath, expected);
console.log(`✓ 已重建 nexus_do.mjs(${expected.length} 字节,注入 index.html ${html.length} 字节)`);
