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

TWA 默认顶部有一条地址栏，配好资产校验才会消失：

1. 拿签名指纹：
   ```bash
   keytool -list -v -keystore android.keystore -alias blackgod | grep SHA256
   ```
2. 把指纹填进 `assetlinks.template.json` 的 `REPLACE_WITH_YOUR_SHA256_FINGERPRINT`，得到最终 JSON。
3. 把这段 JSON 设成 Worker 变量（Worker 已加 `/.well-known/assetlinks.json` 路由，会读它）：
   ```bash
   cd ../web/nexus-do
   npx wrangler secret put ASSETLINKS_JSON   # 粘贴上一步整段 JSON
   ```
   > 也可用普通 var；secret 更稳。设完重新部署。
4. 验证：`https://aquan.lufei.uk/.well-known/assetlinks.json` 返回你的指纹 JSON（不再是 404 提示）。装上 App 冷启一次，地址栏消失即成。

---

## 商店素材（已就位 / 待补）

- [x] 应用图标：`/icon-512.png`（世家 · 神字银灰浮雕 + 玉印，Worker 已提供）
- [x] `manifest.json`：已升商店级（id/scope/shortcuts/maskable/categories/玄墨主题）
- [ ] 商店截图：≥2 张手机竖屏（去分支预览录几张世家界面即可）
- [ ] 一句话简介 / 详情文案：建议主打「认你、懂你、只属于你的私人 AI 意识中枢」
- [ ] 隐私政策链接（Play 与国内商店都要）
- [ ] 国内商店另需：软件著作权（软著）

---

## 包名 / 版本

- packageId：`uk.lufei.aquan.blackgod`（改了要同步改 `assetlinks` 的 `package_name`）
- 每次更新：`appVersionCode` +1、`appVersionName` 改字符串，再 `bubblewrap build`。
