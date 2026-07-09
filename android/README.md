# 神枢 · 安卓上架（TWA）

把已经在跑的 PWA（`web/nexus-do`，域名 `aquan.lufei.uk`）用 **TWA（Trusted Web Activity）**壳成原生安卓包，
上 Google Play / 国内商店，或直接发 APK 侧载。**不重写 App，界面就是现在这套世家 UI。**

> HermesPilot 只有 iOS —— 安卓是它够不着的空档，这一步就是吃这个空档。

---

## 三条路

| 路 | 审核 | 适用 | 产物 |
|---|---|---|---|
| **① 直接发 APK** | 无 | 自己/内测，当天可用 | `app-release-signed.apk` |
| **② Google Play** | 轻、快 | 海外 | `.aab` |
| **③ 国内商店**（华为/小米/OPPO/vivo/应用宝） | 需软著/资质 | 国内 | `.aab` |

技术包三条路同一个，区别只在提交与资质。

---

## 出包步骤（Bubblewrap，10 分钟）

前置：Node ≥ 18、JDK 17。`twa-manifest.json` 已按 `aquan.lufei.uk` 配好。

```bash
cd android
npm i -g @bubblewrap/cli

# 首次：按 twa-manifest.json 生成安卓工程（会让你建/选签名 keystore）
bubblewrap init --manifest ./twa-manifest.json

# 构建（出 APK + AAB）
bubblewrap build
# → app-release-signed.apk（侧载/内测直接用）
# → app-release-bundle.aab（上架用）
```

签名 keystore **务必备份**（`android.keystore` + 口令）——丢了就没法给同一个 App 发更新。

---

## 去掉地址栏（Digital Asset Links）——让它像原生

TWA 默认顶部有一条地址栏，配好资产校验才会消失。**上传密钥的指纹已经内置进 Worker**
（`nexus_do.core.mjs` 的 `ASSETLINKS_JSON` 常量 = `7D:DE:CA:…:DB:78`），
`/.well-known/assetlinks.json` 会直接返回，不再 404。**代码合并部署到 `aquan.lufei.uk` 后即生效。**

启用 **Google Play App Signing**（默认开）后，用户装到的包是 Google 用「应用签名密钥」重签的，
指纹和上传密钥不同。所以首次上传后要把 Google 的那枚指纹**追加**进去：

1. Play Console → 你的应用 → 设置 → 应用完整性 → 「应用签名密钥证书」，复制 SHA-256。
2. 两种加法（二选一）：
   - **改代码**：把该指纹加进 `ASSETLINKS_JSON` 常量的 `sha256_cert_fingerprints` 数组，重新部署；或
   - **不改代码**：给 Worker 设变量 `ASSETLINKS_JSON` 为含**两枚指纹**的完整 JSON（env 覆盖内置值）：
     ```bash
     cd ../web/nexus-do
     npx wrangler secret put ASSETLINKS_JSON
     ```
3. 验证：`https://aquan.lufei.uk/.well-known/assetlinks.json` 返回含 Google 那枚指纹的 JSON。
   装上 App 冷启一次，地址栏消失即成。

> 若上架时**关闭** Play App Signing（自签），则上传密钥即最终签名密钥，内置的这枚指纹就是最终值，无需追加。

---

## 商店素材（已就位 / 待补）

- [x] 应用图标：`/icon-512.png`（世家 · 神字银灰浮雕 + 玉印，Worker 已提供）
- [x] `manifest.json`：已升商店级（id/scope/shortcuts/maskable/categories/玄墨主题）
- [x] 隐私政策链接：`https://aquan.lufei.uk/privacy`（Play 与国内商店的隐私政策 URL 字段都填这个）——
  **提交前先把政策页里的联系邮箱占位符换成真实邮箱**（`web/nexus-do/nexus_do.core.mjs` 里的 `PRIVACY_HTML`）
- [x] 应用简介 / 详情文案 / 关键词：见 `docs/store-listing.md`（短介绍、完整描述、更新说明、关键词，Play 与国内商店都能直接抄）
- [ ] 商店截图：≥2 张手机竖屏（去分支预览录几张世家界面即可）
- [ ] 国内商店另需：软件著作权（软著）

---

## 包名 / 版本

- packageId：`uk.lufei.aquan.blackgod`（改了要同步改 `assetlinks` 的 `package_name`）
- 每次更新：`appVersionCode` +1、`appVersionName` 改字符串，再 `bubblewrap build`。
