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
- [x] **一句话简介 / 详情文案（草稿）**：中英双版已起草 → `docs/store/store-listing-draft.md`
      （字数按 Play/国内商店限制卡好，**待权哥审核后**方可提交）
- [x] **隐私政策页（草稿）**：`web/privacy.html` 已起草，含真实数据收集面（昵称/本地匿名ID/
      自填网关配置/推送订阅/授权制的麦克风与位置），可挂 `aquan.lufei.uk/privacy.html`。
      **状态：草稿，页面顶部有草稿横幅——上线前需删横幅、补对外联系邮箱，经权哥审核后再部署。**
- [ ] **商店截图**：≥2 张手机竖屏。<span>⛔ **待权哥提供**——需从真实预览环境实录，
      我无法虚构截图（也不应伪造）。可在 `aquan.lufei.uk` 或分支预览页手机竖屏截 2-3 张主界面。</span>
- [ ] **对外联系邮箱**：⛔ **待权哥确认**——隐私政策与商店表单都强制要，建议专设一个，别用私人常用邮箱。
- [ ] **国内商店：软件著作权（软著）**：⛔ **待权哥本人办理**——这是行政流程/法律材料，
      不是代码问题，我不能生成或伪造软著证书。需权哥走中国版权保护中心申请。
- [ ] **开发者账号主体**：⛔ **待权哥提供**——Play/国内商店开发者账号的实名/公司主体信息。

> 图例：`[x]` = 已做/已出草稿；`[ ]` + ⛔ = 需权哥本人处理（真实素材/行政材料/账号），
> 不可由代码生成，更不可伪造。

### PWA 本体完整度核查

TWA 壳的就是 `web/nexus-do` 这个网页——网页 UI 没做完，包出来也是半成品。
核查结论（2026-07-12，逐 onclick/addEventListener 入口 + 逐 fetch 端点核对，基线 selftest 83/83 通过）：

**总判断：UI 完整度够上架。** 几乎所有交互都有真实后端支撑，前端 `fetch` 的
15 个端点（`/register /talk /image /voice /video /config /subscribe /vapid /stats` 等）
后端 `nexus_do.core.mjs` 全部有真实路由,无一缺失;出图/语音/视频是真接 Cloudflare
Workers AI 兜底,非假占位;未配置外部网关时诚实降级(明确告知"演示/需配置",不伪造成功);
无 `href="#"` 死链接、无"点了没反应"的死交互。

**✅ 原半成品已修复**（权哥拍板「接进后端让它真生效」）：设置 →「大脑 · 模型」选择器
此前静默无效(选了后端不读)。现已打通:前端 `Nexus.talk` 请求体带上 `model`,后端
`handleTalk`→`callBrain` 经纯函数 `pickBrainOrder(tier, model)` 让选择真正决定后端顺序——
`auto`=按 tier 智能路由;`strong`=强算力网关优先(仍诚实兜底 CF,不假装);`cf-llama`=只用免费内置。
缺省/老客户端等同 `auto`,向后兼容。selftest 88/88(新增 5 项路由测试)。

**⚠ 超出上架范围、但顺带发现需权哥确认**:`CLAUDE.md` 声明"`/api/confirm` 危险操作
二次确认是安全红线,任何重构不得移除",但全文 grep 后端与前端**均无 `/confirm` 路由或
二次确认逻辑**——文档描述的功能在当前代码里不存在。疑为历史文档遗留或计划未实现,
需权哥确认是补功能还是修文档。

---

## 包名 / 版本

- packageId：`uk.lufei.aquan.blackgod`（改了要同步改 `assetlinks` 的 `package_name`）
- 每次更新：`appVersionCode` +1、`appVersionName` 改字符串，再 `bubblewrap build`。
