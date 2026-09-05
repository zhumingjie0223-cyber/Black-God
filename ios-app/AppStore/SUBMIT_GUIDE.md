# App Store 上架指南 · 神枢 Black God

> 本文档面向权哥，按步骤照做即可完成首次上架。所有材料已备齐在本目录下，
> 上架过程中只需复制粘贴，不需要临场写文案。

## 0. 目录速览

```
ios-app/AppStore/
├── SUBMIT_GUIDE.md            ← 本文档
├── screenshots.html           ← 5 张 App Store 截图源文件（HTML+CSS，石墨暗流·玉绿）
├── screenshots_guide.md       ← 截图导出 PNG 操作指南
├── export_screenshots.mjs     ← 截图一键导出脚本（Playwright）
├── PRIVACY_POLICY.md          ← 隐私政策（中英双语，privacy_url 指向它）
└── metadata/
    ├── privacy_url.txt        ← 隐私政策网址
    ├── support_url.txt        ← 技术支持网址（GitHub Issues）
    ├── zh-Hans/               ← 简体中文商店文案
    │   ├── name.txt           App 名称（≤30 字符）
    │   ├── subtitle.txt       副标题（≤30 字符）
    │   ├── description.txt    详细描述（≤4000 字符）
    │   ├── keywords.txt       关键词，英文逗号分隔（≤100 字符）
    │   └── promotional_text.txt 推广文本（≤170 字符，可随时改不用重新审核）
    └── en-US/                 ← 英文商店文案，文件同上
```

工程关键参数（已在 `project.yml` 固定，不要改）：

| 项目 | 值 |
|---|---|
| Bundle ID | `com.blackgod.nexus` |
| 版本号 MARKETING_VERSION | `1.0.0` |
| 构建号 CURRENT_PROJECT_VERSION | `1`（每次上传 +1） |
| 最低系统 | iOS 17.0 |
| 设备 | 仅 iPhone |
| 开发语言 | 简体中文，另附英文本地化 |

---

## 1. 上架前准备（一次性）

- [ ] **Apple Developer Program**：已付费加入（个人或公司账号，99 美元/年）。
- [ ] **Bundle ID 注册**：登录 https://developer.apple.com/account → Identifiers → 新建 App ID，
      填 `com.blackgod.nexus`。Capabilities 不需要勾选任何项（纯客户端，entitlements 为空）。
- [ ] **Xcode 签名**：在 Xcode 里选中 target → Signing & Capabilities → 勾选
      "Automatically manage signing"，Team 选自己的开发者团队。
      （`project.yml` 里 `CODE_SIGNING_ALLOWED: NO` 只影响 CI 无签名构建，真机/发布用 Xcode 自动签名即可。）
- [ ] **App 图标**：确认 `ios-app/AppIcon.png` 为 1024×1024、无透明通道、无圆角（Apple 自己会裁圆角）。
      工程用 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`，首次打包前需在 Xcode 里新建
      `Assets.xcassets` → App Icon，把这张 1024 图拖进去（iOS 17 起只需单尺寸）。
- [ ] **隐私政策网址可访问**：仓库必须是 **Public**，否则审核员打不开
      `metadata/privacy_url.txt` 里的链接。若仓库必须私有，请把 `PRIVACY_POLICY.md`
      另行发布到任意公开网页（GitHub Pages / Cloudflare Pages 均可），再改 `privacy_url.txt`。

## 2. 生成工程并打包

```bash
cd ios-app
brew install xcodegen          # 首次
xcodegen generate              # 由 project.yml 生成 BlackGod888.xcodeproj
open BlackGod888.xcodeproj
```

在 Xcode 中：

1. 顶部设备选 **Any iOS Device (arm64)**。
2. 菜单 **Product → Archive**，等待归档完成，自动弹出 Organizer。
3. Organizer 里选中刚生成的 Archive → **Distribute App** → **App Store Connect** → **Upload**。
   一路默认（勾选自动管理签名、包含 bitcode 选项若有则不勾），点 Upload。
4. 上传成功后约 10~30 分钟，App Store Connect 里会出现该构建版本（期间会收到"已完成处理"邮件）。

> 若报 "No profiles for 'com.blackgod.nexus'"，回到步骤 1 检查 Bundle ID 是否已注册且 Team 选对。

## 3. 在 App Store Connect 创建 App

登录 https://appstoreconnect.apple.com → **我的 App** → 左上 **＋** → **新建 App**：

| 字段 | 填写 |
|---|---|
| 平台 | iOS |
| 名称 | 粘贴 `metadata/zh-Hans/name.txt` 内容：`神枢 Black God` |
| 主要语言 | 简体中文 |
| 套装 ID | 选 `com.blackgod.nexus` |
| SKU | `blackgod-nexus-ios`（内部编号，随意但唯一） |
| 用户访问权限 | 完全访问 |

## 4. 填写商店信息（中文，主要语言）

进入 App → **1.0 准备提交** 页面：

1. **截屏**：至少上传 6.7 英寸（iPhone 15 Pro Max / 16 Pro Max）尺寸 1290×2796 的截图 3~10 张。
   **成品已备好**：`screenshots.html` 里有 5 张带营销标语的精修图（主对话 → API Key 配置 →
   多模型选择 → 神枢监测 → 隐私安全），按 `screenshots_guide.md` 一键导出 PNG 后直接上传，
   不必再用模拟器裸截。（6.5 英寸尺寸 Apple 可自动缩放复用 6.7 英寸的，不用单独做。）
2. **推广文本** ← `metadata/zh-Hans/promotional_text.txt`
3. **描述** ← `metadata/zh-Hans/description.txt`
4. **关键词** ← `metadata/zh-Hans/keywords.txt`
5. **技术支持网址** ← `metadata/support_url.txt`
6. **营销网址**：可留空。
7. **副标题**（在页面上方"App 信息"区）← `metadata/zh-Hans/subtitle.txt`
8. **版本**：`1.0.0`
9. **版权**：`© 2026 Black God`
10. **构建版本**：点 ＋ 选择步骤 2 上传的那个 build。

## 5. 添加英文本地化

在版本页右上角语言下拉 → **添加语言** → **英语（美国）**，然后把 `metadata/en-US/` 五个文件
逐项粘贴到对应字段（名称、副标题、推广文本、描述、关键词）。截图可复用中文的，
或用英文系统语言的模拟器再截一套。

## 6. App 信息 / 分级 / 隐私（左侧栏）

### App 信息
- **类别**：主要 **效率**（Productivity），次要 **工具**（Utilities）。
- **内容版权**：不包含第三方内容。
- **隐私政策网址** ← `metadata/privacy_url.txt`

### 年龄分级
按问卷全部选"无"，最终得到 **4+**。
（AI 生成内容不需要额外标注，但下方审核备注里会说明。）

### App 隐私（重点，审核最常卡这里）
- 问"是否收集数据" → **否，我们不会从此 App 收集数据**。
  依据：无账号、无埋点、无第三方 SDK，Key 和聊天记录只存本机。
  对话内容发送给 Anthropic 是用户使用自己 Key 主动发起的，不属于开发者收集。
- 保存后隐私标签会显示"未收集数据"。

### 定价与销售范围
- 价格：**免费**。
- 销售范围：全部国家/地区（如需只发中国大陆 + 美国也可以，按需勾选）。
- **注意**：中国大陆区上架 App 若含"互联网信息服务"可能被要求提供 ICP 备案号。
  本 App 零后端、无自有服务，若被要求，可在"审核备注"中说明并申诉；
  若坚持要求，可先取消勾选中国大陆，其它地区照常上线。

### 出口合规（加密）
上传构建后会问"是否使用加密"。本 App 仅使用 HTTPS 标准加密：
- 选 **是** → 再选 **仅使用 Apple 操作系统内置的加密或标准加密（HTTPS/TLS）** → 免于提交文档。
- 为避免每次上传都问，可在 `project.yml` 的 `info.properties` 加
  `ITSAppUsesNonExemptEncryption: false`（已加，见工程文件）。

## 7. 审核备注（App 审核信息 → 备注）

复制粘贴以下内容，能大幅减少被审核员误判为"需要登录/功能不完整"的概率：

```
本 App 是纯客户端的 AI 对话工具，无自有服务器、无账号系统。
用户需自行在 console.anthropic.com 申请 Anthropic API Key 并在 App 设置中填入，
App 直接调用 Anthropic 官方 API 完成对话。Key 存储在 iOS Keychain，聊天记录存储在本机。

测试用 API Key（仅供审核，有额度限制）：sk-ant-api03-XXXXXXXX
填入路径：打开 App → 底部"我的" → "神枢连接" → 粘贴 Key → 保存 → 回到"对话"页发送消息。

模型回复内容由 Anthropic Claude 生成，本 App 不做任何内容修改。
```

> **务必**在提交前去 https://console.anthropic.com 建一个单独的、设置了低月度额度上限的
> Key 给审核员，审核通过后立即吊销。

**联系信息**：填自己的姓名、电话、邮箱（审核员有问题会打电话/发邮件）。
**登录信息**：选"不需要登录"。

## 8. 提交与发布

1. 页面顶部 **添加以供审核** → 检查所有黄点警告都消掉 → **提交以供审核**。
2. 发布方式建议选 **手动发布**，审核通过后自己点"发布"，方便控制时间。
3. 审核状态邮件通知；首次审核一般 24~48 小时，被拒会附具体条款和截图。

## 9. 常见被拒原因与应对

| 拒审条款 | 原因 | 应对 |
|---|---|---|
| Guideline 2.1 – 无法完成审核 | 审核员没填 Key 就说功能不可用 | 审核备注里给测试 Key + 精确到点击的填入路径（第 7 步模板） |
| Guideline 5.1.1 – 数据收集 | 隐私标签与实际不符 | 确认标签为"未收集数据"，隐私政策网址可公开访问 |
| Guideline 4.2 – 最低功能 | 认为是简单网页套壳 | 回复中强调：原生 SwiftUI、Keychain、流式输出、快捷指令集成 |
| Guideline 1.2 – 用户生成内容 | AI 生成内容无过滤 | 回复：内容由 Anthropic 生成，受 Anthropic 使用政策约束；App 仅为个人工具，无社交/分享功能 |
| Guideline 3.1.1 – 应用内购买 | 误认为 API Key 是绕过 IAP 的付费 | 回复：Key 由用户自行在第三方获取，App 不销售任何数字商品，属 3.1.3(b) 允许范围 |

## 10. 后续版本更新

1. `project.yml` 里 `MARKETING_VERSION` 改成新版本号（如 `1.0.1`），`CURRENT_PROJECT_VERSION` +1。
2. `xcodegen generate` → Archive → Upload。
3. App Store Connect 里 **＋ 版本** → 填"此版本的新增内容"（中英各一份）→ 选新 build → 提交。
4. 只改推广文本/截图不需要发新版本，可随时改。

---

### 铁律回顾
- Bundle ID `com.blackgod.nexus` 一旦提交 **不可更改**，提交前再核对一次。
- 审核 Key 用完立即吊销。
- 仓库保持 Public，否则隐私政策链接失效导致拒审。
