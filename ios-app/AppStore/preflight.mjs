#!/usr/bin/env node
// App Store 上架就绪校验器 · 神枢 Black God iOS
// 纯 Node、零依赖。把上架前必须满足的硬约束一次性自动核对,输出清单。
// 任一红项 → 退出码 1(可作 CI / environment.json install 的上架闸门)。
//
// 用法: node ios-app/AppStore/preflight.mjs   (也可在 ios-app/AppStore/ 目录内直接 node preflight.mjs)
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const HERE = path.dirname(fileURLToPath(import.meta.url)); // ios-app/AppStore
const IOS = path.dirname(HERE);                            // ios-app
const ROOT = path.dirname(IOS);                            // 仓库根

let pass = 0, fail = 0;
const rows = [];
const ok = (m) => { pass++; rows.push(['✅', m]); };
const bad = (m) => { fail++; rows.push(['❌', m]); };
const read = (p) => readFileSync(p, 'utf8');
const cps = (s) => [...s.trim()].length; // 按 Unicode 码点计字符数(贴近 App Store 计法)

// ── 读取工程定义 project.yml ──
const projPath = path.join(IOS, 'project.yml');
if (!existsSync(projPath)) { bad(`缺少 ${path.relative(ROOT, projPath)}`); report(); }
const proj = read(projPath);
const pick = (re, src = proj) => (src.match(re)?.[1] ?? '').trim();
const projName = pick(/^name:\s*(\S+)/m);
const bundleId = pick(/PRODUCT_BUNDLE_IDENTIFIER:\s*([\w.]+)/);
const marketing = pick(/MARKETING_VERSION:\s*"?([\d.]+)"?/);
const buildNo = pick(/CURRENT_PROJECT_VERSION:\s*"?(\d+)"?/);
const encExempt = /ITSAppUsesNonExemptEncryption:\s*(false|true|NO|YES)/i.test(proj);

projName ? ok(`工程名 name = ${projName}`) : bad('project.yml 缺少 name');
/^com\.[\w.]+$/.test(bundleId) ? ok(`Bundle ID = ${bundleId}`) : bad(`Bundle ID 非法或缺失: "${bundleId}"`);
/^\d+\.\d+\.\d+$/.test(marketing) ? ok(`版本号 MARKETING_VERSION = ${marketing}(合法三段式)`) : bad(`MARKETING_VERSION 非三段式: "${marketing}"`);
/^\d+$/.test(buildNo) ? ok(`构建号 CURRENT_PROJECT_VERSION = ${buildNo}`) : bad(`构建号非正整数: "${buildNo}"`);
encExempt ? ok('已声明 ITSAppUsesNonExemptEncryption(免出口合规文档)') : bad('project.yml 未声明 ITSAppUsesNonExemptEncryption');

// ── CI 配置与工程一致 ──
const cmPath = path.join(ROOT, 'codemagic.yaml');
if (existsSync(cmPath)) {
  const cm = read(cmPath);
  const cmScheme = pick(/XCODE_SCHEME:\s*(\S+)/, cm);
  const cmBundle = pick(/bundle_identifier:\s*([\w.]+)/, cm);
  cmScheme === projName ? ok(`codemagic scheme 与工程一致(${cmScheme})`) : bad(`codemagic XCODE_SCHEME=${cmScheme} ≠ 工程名 ${projName}`);
  cmBundle === bundleId ? ok(`codemagic bundle 与工程一致(${cmBundle})`) : bad(`codemagic bundle_identifier=${cmBundle} ≠ ${bundleId}`);
} else bad('缺少 codemagic.yaml');

const bwPath = path.join(ROOT, '.github/workflows/build.yml');
if (existsSync(bwPath)) {
  const bw = read(bwPath);
  /-scheme\s+BlackGod888/.test(bw) && new RegExp(`-scheme\\s+${projName}`).test(bw)
    ? ok(`build.yml scheme 与工程一致(${projName})`)
    : bad(`build.yml 的 -scheme 与工程名 ${projName} 不一致`);
} else rows.push(['➖', 'build.yml 不存在(可选,跳过)']);

// ── 上架文档版本号一致(SUBMIT_GUIDE) ──
const guidePath = path.join(HERE, 'SUBMIT_GUIDE.md');
if (existsSync(guidePath)) {
  const guide = read(guidePath);
  const guideVers = [...guide.matchAll(/MARKETING_VERSION\s*\|\s*`([\d.]+)`|\*\*版本\*\*[：:]\s*`([\d.]+)`/g)]
    .map(m => m[1] || m[2]).filter(Boolean);
  const mismatchV = guideVers.filter(v => v !== marketing);
  mismatchV.length === 0 && guideVers.length > 0
    ? ok(`SUBMIT_GUIDE 版本号与工程一致(${marketing})`)
    : bad(`SUBMIT_GUIDE 版本号 [${guideVers.join(', ')}] 与工程 ${marketing} 不一致`);
} else bad('缺少 AppStore/SUBMIT_GUIDE.md');

// ── 商店文案(中英双语)齐全且长度合规 ──
const LIMITS = { name: 30, subtitle: 30, keywords: 100, promotional_text: 170, description: 4000, release_notes: 4000 };
const REQUIRED = ['name', 'subtitle', 'description', 'keywords', 'promotional_text'];
for (const lang of ['zh-Hans', 'en-US']) {
  const dir = path.join(HERE, 'metadata', lang);
  if (!existsSync(dir)) { bad(`缺少 metadata/${lang}/ 目录`); continue; }
  for (const key of REQUIRED) {
    const fp = path.join(dir, `${key}.txt`);
    if (!existsSync(fp)) { bad(`缺少 metadata/${lang}/${key}.txt`); continue; }
    const n = cps(read(fp));
    if (n === 0) { bad(`metadata/${lang}/${key}.txt 为空`); continue; }
    const lim = LIMITS[key];
    n <= lim ? ok(`metadata/${lang}/${key} = ${n} 字符(≤${lim})`) : bad(`metadata/${lang}/${key} = ${n} 字符,超过上限 ${lim}`);
  }
  // release_notes 若存在也校验长度并核对版本号出现
  const rn = path.join(dir, 'release_notes.txt');
  if (existsSync(rn)) {
    const txt = read(rn); const n = cps(txt);
    n <= LIMITS.release_notes ? ok(`metadata/${lang}/release_notes = ${n} 字符(≤4000)`) : bad(`metadata/${lang}/release_notes 超 4000 字符`);
    txt.includes(marketing) ? ok(`metadata/${lang}/release_notes 提到版本 ${marketing}`) : bad(`metadata/${lang}/release_notes 未提到当前版本 ${marketing}`);
  }
}

// ── 隐私政策与支持链接 ──
for (const [f, label] of [['privacy_url.txt', '隐私政策网址'], ['support_url.txt', '技术支持网址']]) {
  const fp = path.join(HERE, 'metadata', f);
  if (!existsSync(fp)) { bad(`缺少 metadata/${f}`); continue; }
  const u = read(fp).trim();
  /^https:\/\/\S+$/.test(u) ? ok(`${label} 是 https 链接`) : bad(`${label} 不是合法 https 链接: "${u}"`);
}
existsSync(path.join(HERE, 'PRIVACY_POLICY.md')) ? ok('隐私政策正文 PRIVACY_POLICY.md 存在') : bad('缺少 PRIVACY_POLICY.md');
existsSync(path.join(HERE, 'screenshots.html')) ? ok('截图源 screenshots.html 存在') : bad('缺少 screenshots.html');

// ── App 图标:1024×1024、PNG、无 alpha(App Store marketing icon 硬要求) ──
function pngInfo(fp) {
  const b = readFileSync(fp);
  if (b.length < 26 || b.readUInt32BE(0) !== 0x89504e47) return null;
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20), colorType: b[25] };
}
const iconCandidates = [
  path.join(IOS, 'Assets.xcassets/AppIcon.appiconset/AppIcon.png'),
  path.join(IOS, 'AppIcon.png'),
];
const iconPath = iconCandidates.find(existsSync);
if (!iconPath) bad('找不到 AppIcon.png');
else {
  const info = pngInfo(iconPath);
  const rel = path.relative(ROOT, iconPath);
  if (!info) bad(`${rel} 不是合法 PNG`);
  else {
    info.w === 1024 && info.h === 1024 ? ok(`App 图标 ${rel} = 1024×1024`) : bad(`App 图标 ${rel} = ${info.w}×${info.h},必须 1024×1024`);
    const hasAlpha = info.colorType === 4 || info.colorType === 6;
    hasAlpha ? bad(`App 图标含 alpha 通道(colorType=${info.colorType}),App Store 不接受透明图标`) : ok('App 图标无 alpha 通道');
  }
}

// ── Xcode 资源目录(若已内置 asset catalog 则校验其引用完整) ──
const iconset = path.join(IOS, 'Assets.xcassets/AppIcon.appiconset');
if (existsSync(iconset)) {
  const contents = path.join(iconset, 'Contents.json');
  if (!existsSync(contents)) bad('AppIcon.appiconset 缺少 Contents.json');
  else {
    let j; try { j = JSON.parse(read(contents)); } catch { j = null; }
    if (!j) bad('AppIcon.appiconset/Contents.json 不是合法 JSON');
    else {
      const files = (j.images || []).map(i => i.filename).filter(Boolean);
      const missing = files.filter(f => !existsSync(path.join(iconset, f)));
      missing.length === 0 && files.length > 0
        ? ok(`asset catalog 图标已内置(${files.join(', ')}),工程可直接打包`)
        : bad(`asset catalog 引用的图标文件缺失: ${missing.join(', ') || '(空)'}`);
    }
  }
  // project.yml 是否把 Assets.xcassets 纳入 sources
  /Assets\.xcassets/.test(proj) ? ok('project.yml 已把 Assets.xcassets 纳入 target') : bad('Assets.xcassets 存在但未写进 project.yml 的 sources');
} else {
  rows.push(['➖', 'Assets.xcassets 未内置:需在 Xcode 手动导入 1024 图标(见 SUBMIT_GUIDE)']);
}

// ── 所有 Swift 源都在工程根下(会被 project.yml 的 **/*.swift 纳入) ──
const swiftCount = readdirSync(IOS).filter(f => f.endsWith('.swift')).length;
swiftCount > 0 ? ok(`工程根含 ${swiftCount} 个 .swift(由 **/*.swift 纳入编译)`) : bad('工程根未发现 .swift 源文件');

report();

function report() {
  console.log('\n══════ App Store 上架就绪校验 · 神枢 Black God iOS ══════\n');
  for (const [icon, msg] of rows) console.log(`  ${icon}  ${msg}`);
  console.log(`\n  合计: ${pass} 通过 / ${fail} 失败\n`);
  if (fail > 0) { console.error(`✗ 上架就绪校验未通过:${fail} 项需修复\n`); process.exit(1); }
  console.log('✓ 上架就绪校验全绿:iOS 上架所需的工程配置、文案、图标、隐私材料均已达标\n');
  process.exit(0);
}
