# 神枢 Black God · App Store 提交指南

本目录对应 iPhone 发布候选版本 **1.1.0（2）**。本地检查通过、上传构建、提交审核和商店发布是不同状态；只有 App Store Connect 的实际结果能证明后面三项已完成。账户信息和未验证事项见下文，不使用占位资料提交。

## 工程与材料

| 项目 | 值 |
|---|---|
| Bundle ID | `com.blackgod.nexus` |
| MARKETING_VERSION | `1.1.0` |
| CURRENT_PROJECT_VERSION | `2` |
| 开发者 Team | `8429ZL8NQ9`（上传账号须有该团队权限） |
| 最低系统 / 设备 | iOS 17.0 / iPhone |
| 界面 | 主要为简体中文，部分导航和系统文本支持英文 |
| 商店文案 | `metadata/zh-Hans/`、`metadata/en-US/` |
| 隐私说明 | `PRIVACY_POLICY.md`；同时打包供「我的 → 隐私政策」查看 |
| 审核流程 | `REVIEW_NOTES.md` |
| 隐私问卷依据 | `PRIVACY_ASSESSMENT.md` |
| 截图要求 | `screenshots_guide.md` |

保留现有深墨绿品牌和「神」字图标。图标已在 `Assets.xcassets/AppIcon.appiconset/` 内，无需重复创建资源。版本号与构建号以 `project.yml` 为准；上传过的构建号不要复用。

## 提交前必须完成的内容

- [ ] Apple Developer 会员、协议、App Store Connect 访问和签名资格有效；核实 Bundle ID 属于正确团队。
- [ ] 确定实际发布主体、版权持有人、审核联系人姓名/电话/邮箱。当前仓库无法验证这些身份资料。
- [ ] 在 App Store Connect 创建或找到对应 App 记录，选定 1.1.0 构建 2。
- [ ] 在真机完成 API 配置、共享同意/拒绝/撤回、真实模型回复、取消、切换服务商和本地清除测试。每个上架的模型都需验证账户实际可用。
- [ ] 提供审核员可用的专用测试凭据、模型和操作路径。凭据应有合理额度并在审核期间有效，写入 App Store Connect 私密审核信息；不进仓库、公开文案或截图。
- [ ] 按 `PRIVACY_ASSESSMENT.md` 核实服务商 API 保留及账户关联行为，完成 App 隐私问卷。不能因自带 Key 就断言「未收集数据」。
- [ ] 按当前分级问卷回答实际功能和内容频率，完成 AI 输出及内容安全测试；不把全部选「无」或 4+ 作为默认答案。[Apple 年龄分级说明](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [ ] 确定价格、销售地区和发布时机，核实各模型服务商在这些地区的可用性及服务条款。当前代码不销售额度或订阅；自带 API Key 不自动证明符合任何特定付费例外。
- [ ] 核实第三方内容权利、加密申报及地区资料。中国大陆发行资格和欧盟交易者身份需用真实资料填写，不能从「无自有后端」推导豁免。[中国大陆资料](https://developer.apple.com/help/app-store-connect/manage-compliance-information/view-china-mainland-compliance-information/)、[欧盟交易者要求](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)
- [ ] 发布更新后的隐私政策并匿名打开测试；当前 `privacy_url.txt` 指向 GitHub **main**，本地改动或 PR 不会自动更新该页面。核实支持链接可用，并补齐发布主体与适用的私密联系方式。
- [ ] 使用最终构建的真实截图，核对无 Key、真实个人数据、虚构回复或尚未实现的功能。旧 HTML 样稿须先与真实 UI 对照。

Apple 要求商店信息与实际功能一致，并提供可完成审核的版本；隐私说明应在 App 内可达，第三方 AI 数据共享需明确告知并先获许可。本版本增加了按服务商保存的共享选择，仍需验证发布包行为。[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## 本地构建与 fastlane

需要当前 Apple 接受的 Xcode、xcodegen、Ruby/fastlane 和 Node。`node AppStore/preflight.mjs` 检查文件、文案长度等静态条件，不核验 Apple 账号、服务商可用性、线上政策或法律问卷。

```bash
cd ios-app
node AppStore/preflight.mjs
fastlane build
```

`build` 生成 Xcode 工程、归档并导出签名 IPA 到 `ios-app/build/BlackGod888.ipa`。签名需要有效证书和描述文件；无签名构建不能上传 App Store。

认证采用 `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8` 三个环境变量，其中最后一项是私密 `.p8` 文件的绝对路径。也可设置 `APPLE_ID` 使用 fastlane 的正常登录流程；多团队时使用 `ASC_TEAM_ID`（App Store Connect 团队）和 `APPLE_TEAM_ID`（签名团队）。这些值不要写进仓库。

提供已经检查过的实际 App 截图目录，结构为 `目录/zh-Hans/*.png` 和 `目录/en-US/*.png`。目前流水线接受 6.9 英寸规格的 RGB、不透明、竖版 PNG，详见截图指南。调用时设置该目录的绝对路径为 `ASC_SCREENSHOTS_DIR`。

```bash
# 构建并上传二进制、文案、提供的截图；不会自动提交审核
fastlane release

# 或上传已有 IPA：先将 IPA_PATH 设为该 IPA 的绝对路径
fastlane upload
```

流水线不再自动生成或上传 HTML 模拟截图。`release` 不代表已上架；上传后要等 Apple 处理构建并核验 App Store Connect 内容。年龄分级、隐私、价格、地区等字段可在 App Store Connect 完成；不宣称它们只能手动操作。fastlane 的不同动作支持不同字段。[fastlane 上传文档](https://docs.fastlane.tools/actions/upload_to_app_store/)

## 审核资料与提交

可直接在 App Store Connect 选择明确版本和构建并提交；也可运行独立的 `fastlane submit`。该 lane 从环境变量 `ASC_SUBMISSION_CONFIG` 指向的**私密 JSON 文件**读取实际审核信息和申报答案，拒绝缺失、未填写、非布尔申报以及不匹配的版本/构建。以下只是结构示例，`PENDING` 和 `null` 必须替换后才能使用：

```json
{
  "app_version": "1.1.0",
  "build_number": "2",
  "copyright": "PENDING",
  "automatic_release": null,
  "app_review_information": {
    "first_name": "PENDING",
    "last_name": "PENDING",
    "phone_number": "PENDING",
    "email_address": "PENDING",
    "notes": "PENDING"
  },
  "submission_information": {
    "export_compliance_uses_encryption": null,
    "content_rights_contains_third_party_content": null,
    "add_id_info_uses_idfa": null
  }
}
```

`notes` 依据 `REVIEW_NOTES.md`，并在私密文件中补充有效测试凭据。`automatic_release` 决定审核通过后自动发布（true）或等待手动发布（false）；按实际发行安排填写。JSON 不能替代 App Store Connect 中的完整隐私、年龄和地区申报。

App 使用系统 HTTPS 与 Keychain，`ITSAppUsesNonExemptEncryption: false` 表达「不使用非豁免加密」，与「完全未使用加密」不同。按最终包和 Apple 问卷核实具体答案，不从这个值自动生成全部申报。[Apple 出口合规说明](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)

```bash
fastlane submit
```

`submit` 选择 JSON 中的确切版本和构建，提交审核而不重传二进制与截图。发布结果、处理时间、审核反馈以 Apple 返回状态为准。后续改动需同步版本文案、隐私政策和截图；不要承诺所有字段都能在上线后随时修改。
