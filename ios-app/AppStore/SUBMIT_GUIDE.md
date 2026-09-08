# Black God 发布流程

更新：2026-09-09。此文件替换旧版仅支持 Anthropic 的草案。不能把构建成功、测试通过或 IPA 导出称为已上架。

## 当前发布配置

- 名称：Black God；Bundle ID：com.blackgod.nexus。
- 版本 1.2.0，构建 4，iPhone，最低 iOS 17。
- 本机已找到匹配 Bundle ID 的 App Store 分发描述文件及发布证书。团队 ID 8429ZL8NQ9 只在归档命令中传入，不改动用户全局 Xcode 账号。
- 真实模型账号联调尚未完成。现有 Xcode/Transporter 登录已成功上传 1.2.0（3），App ID 6809828368；Transporter 2026-09-09 04:06（UTC+7）显示已交付；后续 Transporter 已确认 APP 完成处理。App Store Connect 网页持续返回 502 / authResult=FAILED，尚未提交 App Review。

## 构建 4 更新

内置 Alpine 升级为 3.22.5，并通过 apk 签名验证安装 OpenSSL 3.5.8。升级保留旧运行环境，只迁移用户工作区；文件/索引不完整时停止迁移，不静默丢弃。工作区初始化可恢复中断。新增应用内开源许可和真实版本显示。221 项不同单元测试、3 项界面测试通过；16 个安装包完成 144 次 Alpine secdb 修复版本对比，无落后项。新构建的上传状态须单独确认，不能沿用构建 3 的成功状态。

## 构建 3 更新

Claude 官方 API 配置支持可选 Workspace ID。Claude.ai 订阅登录不作为 Black God 原生 OAuth 实现；OpenRouter 授权后的 Claude 使用 OpenRouter 的账号额度。

新增按连接的数据发送许可，聊天和原生工具回合请求前强制检查。应用内可阅读完整隐私政策。隐私清单包含文件元数据、应用定时、磁盘空间与本机偏好所需理由。真实磁盘空间只用于本机显示/写入保护；Linux statfs 返回逻辑工作空间预算，避免工具输出携带手机真实磁盘容量。

商店中英文文案已按当前能力重写。不得复用旧文案中的“不发送任何数据”“密钥不会离开设备”“一键删除全部”“已上线”或“所有分级都填无”。不得使用旧 screenshots.html 的模拟聊天截图冒充真实运行截图。

## 可复现的本地归档

在仓库运行 xcodegen generate --spec ios-app/project.yml，然后使用 xcodebuild archive：

- project：ios-app/BlackGod.xcodeproj；scheme：BlackGod；configuration：Release；destination：generic/platform=iOS。
- DEVELOPMENT_TEAM=8429ZL8NQ9；CODE_SIGN_STYLE=Automatic；CODE_SIGN_IDENTITY=Apple Development。
- 不传手动 PROVISIONING_PROFILE_SPECIFIER；现有描述文件由 Xcode 自动管理。
- archivePath 指向工作目录中的 .xcarchive。

导出使用 method=app-store-connect、destination=export、signingStyle=automatic、teamID，允许使用 Xcode 已登录账号更新发布描述文件。先本地导出并校验签名；是否上传以及最终构建号要以 App Store Connect 的真实状态为准。

## 提交前仍需完成

1. 使用真实且有额度的账号验证 Claude/其他拟发布连接的对话、工具回传和授权刷新；提供审核可用的受限凭据或可审核的演示入口，不把占位密钥提交给 Apple。
2. 在 App Store Connect 完成登录，核实应用与构建记录，填写真实审核联系人、地区、价格、内容权利和年龄分级。不能编造信息或代替用户接受未审阅的合同。
3. 已通过设备现有 GitHub 登录发布隐私政策，提交 6f80179077c60f3dbf37aafd0ef2832a775bdd50；匿名读取公共 raw 页面与包内文件逐字节一致。仍需在 App Store Connect 核实隐私网址字段。
4. 按实际第三方服务数据行为填写隐私标签。当前清单按账号关联的用户内容和账号识别信息声明应用功能用途、无追踪；服务商保留策略仍需核对，不默认填“未收集数据”。
5. 核验内置 iSH/Alpine 及修改源码的许可、源码提供与分发义务；明确说明解释执行、软件包与联网能力，按 Apple 对可执行代码和小程序/插件的实际适用要求准备审核说明。
6. 为新增 CLI OAuth 兼容路线确认客户端登记与分发权限，不把能握手称为厂商正式授权合作。
7. 使用当前二进制的真实截图与测试记录，完成真机前后台、取消、存储不足与网络切换验证。截图尺寸以 Apple 当前文档和后台要求为准。
8. 上传后等待 Apple 处理与审核；状态必须从后台核实。审核未通过或未发布时，不对外宣称上线。

## 官方参考

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- https://code.claude.com/docs/en/legal-and-compliance

## 源码发行记录

2026-09-09，源码分支 codex/release-readiness 已发布，提交 fdd26f55b2fe67ba42a3f3bd7d5ef813dd390b8a。对应源码与校验清单已公开于 [https://github.com/zhumingjie0223-cyber/Black-God/releases/tag/v1.2.0-build3](https://github.com/zhumingjie0223-cyber/Black-God/releases/tag/v1.2.0-build3)，标记为开发预发布。归档含 2,028 个文件及 Alpine 16 个包的 10 组源码，122 个上游 SHA-512 输入校验全部通过；5 项源码完整性测试通过。两个公开附件的 GitHub digest 与本地 SHA-256 完全相同。公开源码解决源码访问问题，不表示账号 API、真机验收或 App Review 已完成。
