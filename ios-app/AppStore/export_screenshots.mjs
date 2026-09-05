#!/usr/bin/env node
// export_screenshots.mjs — 神枢 App Store 截图一键导出（HTML → PNG）
//
// 用法（在 ios-app/AppStore/ 目录下）：
//   npm i -D playwright && npx playwright install chromium   # 首次安装
//   node export_screenshots.mjs                              # 导出 6.7″ 1290×2796 → ./png/6_7/
//   node export_screenshots.mjs --size 6.9                   # 导出 6.9″ 1320×2868 → ./png/6_9/
//
// 原理：页面每张截图为 393×852 CSS 像素。以「目标高度 ÷ 852」作为设备像素比渲染，
//       再按目标宽度居中裁切，可得到像素级精确的 PNG（已逐张校验尺寸）。
//       App Store Connect 只要求 6.9″ 或 6.7″ 其一，其余小尺寸机型由 Apple 自动缩放。

import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { mkdirSync } from 'node:fs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const sizeArg = args.includes('--size') ? args[args.indexOf('--size') + 1] : '6.7';

const PRESETS = {
  '6.7': { w: 1290, h: 2796 },   // iPhone 14 Pro Max / 15 Pro Max / 16 Plus
  '6.9': { w: 1320, h: 2868 },   // iPhone 16 Pro Max / 17 Pro Max
};
const preset = PRESETS[sizeArg];
if (!preset) { console.error(`不支持的尺寸：${sizeArg}，可选 ${Object.keys(PRESETS).join(' / ')}`); process.exit(1); }

const outDir = resolve(here, 'png', sizeArg.replace('.', '_'));
mkdirSync(outDir, { recursive: true });

const k = preset.h / 852;                 // 设备像素比：按高度对齐
const browser = await chromium.launch();
const ctx = await browser.newContext({ deviceScaleFactor: k, viewport: { width: 2100, height: 900 } });
const page = await ctx.newPage();
await page.goto('file://' + resolve(here, 'screenshots.html') + '?export');
await page.waitForTimeout(500);           // 等字体与滤镜稳定

const shots = await page.$$('section.shot');
let bad = 0;
for (const el of shots) {
  const id = await el.getAttribute('id');
  const title = await el.getAttribute('data-title');
  const n = id.replace('shot-', '');
  const box = await el.boundingBox();
  const cw = preset.w / k;                // 目标宽度对应的 CSS 像素宽
  const buf = await page.screenshot({
    type: 'png',
    clip: { x: box.x + (box.width - cw) / 2, y: box.y, width: cw, height: box.height },
  });
  const W = buf.readUInt32BE(16), H = buf.readUInt32BE(20);   // 读 PNG 头核验尺寸
  const ok = W === preset.w && H === preset.h;
  if (!ok) bad++;
  const file = resolve(outDir, `${n}-${title}.png`);
  (await import('node:fs/promises')).writeFile(file, buf);
  console.log(`${ok ? '✓' : '✗'} ${file}  ${W}×${H}`);
}
await browser.close();
console.log(`\n完成：${shots.length} 张 → ${outDir}（目标 ${preset.w}×${preset.h}）${bad ? `，有 ${bad} 张尺寸不符，请检查` : ''}`);
process.exit(bad ? 1 : 0);
