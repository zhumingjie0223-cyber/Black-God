# Black God 发布流程

更新：2026-09-24。此文件替换旧版仅支持 Anthropic 的草案。不能把构建成功、测试通过或 IPA 导出称为已上架。

## 当前发布配置

- 名称：Black God；Bundle ID：com.blackgod.nexus。
- 公开在售版本为 **1.2.1**，Apple 官方公开查询的发布时间为 2026-09-21T20:30:16Z（2026-09-24 核实，App ID 6809828368）。[商店页面](https://apps.apple.com/app/id6809828368)。
- **已上架版本**使用 iPhone 设备族，iPad 以兼容模式运行；不能把本地改动视为商店现有能力。
- **本轮发布候选**为 1.3.0（12），最低 iOS 17；`TARGETED_DEVICE_FAMILY: "1,2"` 包含原生 iPad 侧栏与横竖屏。2026-09-24 核实后台已有较早的 1.3.0（11）等待审核，本轮完整升级使用构建12替换。正式上架状态以 Apple 后台及本次发布记录为准。
- 本轮已验证匹配 Bundle ID 的开发签名，并完成构建12的 Release 签名归档。团队 ID 8429ZL8NQ9 只在发布命令中传入，不改动全局 Xcode 账号。
- 真实模型与真机验收不能由已上架状态替代，参见 [工业级验收门槛](../../docs/quality/工业级验收门槛.md)。
- 以下构建 3–7 及旧后台错误均为 2026-09-09 的历史记录，不代表当前商店状态。后续发布过程见 docs/done 的 2026-09-21 记录。

## 本地升级与验证状态（2026-09-24）

本地界面保留原黑绿主色，主导航为“对话、创作、监测、我的”。独立工具主页面已删除，相关功能进入“我的 → 高级设置”；连接面板、按钮层级与任务状态展示已重构。提交文案和截图必须对应最终待上传的二进制，不沿用旧导航，也不把模拟器通过写成真机验收通过。

全量 322 项 iOS 单元测试通过，之后新增的 2 项直播回归也通过；8 项直播用例在定向检查与冷启动等待修正后的复测中全部通过（共 324 个不同单元用例，不是最终源码全量重跑）。iPhone 17 个界面场景首轮 15 项通过，2 项失败经修正定向复验通过；iPad 2 个场景通过，涵盖四页导航、侧栏及横竖屏。最终源码 Release 设备目标无签名构建通过。 此前枢语 123 项 JS／55 项 Python 通过，资源一致性复验通过；原生库和签名校验、版本锁定的 rootfs 已重建。真机结果、真实服务商、公开隐私说明同步和签名归档须在发版前单独确认。验证详情见 [本轮完成记录](../../docs/done/2026-09-24-黑绿界面重构与Shell直播验收.md)。

2026-09-24 已为用户 iPhone 17 Pro Max（iOS 26.7）生成含该设备的开发描述文件，严格签名检查后覆盖安装并启动，旧聊天文件保留。当时仅完成本地开发包安装；后续正式发行使用1.3.0（12），[真机安装记录](../../docs/done/2026-09-24-新版真机安装与启动检查.md)仅证明本次最小启动检查。

## 构建 7：自我状态流开发版

新增事件驱动的自我状态记录、运行绑定公开自评工具、暂停/清空和重启中断处理。没有主观意识证明或后台持续推理。本轮242项单元测试、3项界面测试通过（含新增9项状态流测试）。构建6的签名或上传状态不代表构建7，真实账号与真机验收仍待完成。公共隐私政策仍需同步。

## 构建 6：神枢成长开发版

增加线性因果模型干预计算、任务依赖检查、知识候选与核对流程、限时模型工具授权、可撤销权限与本机审计、用户选图的本机OCR。没有主观意识证明、权重自训练或机器人/实验设备适配。233项单元测试和2项界面测试通过；OCR使用真实Vision识别合成测试图片。完整机制和限制见docs/COGNITIVE_CONTROL.md。

当前开发版尚未作为正式发布验收完成。新隐私说明须同步到公开隐私网址，真实模型账号及真机验收仍需完成；不能把之前build5的Apple上传状态当作build6的状态。

## 构建 5 更新

修复完整开源许可单个超长文本无法绘制的问题，采用分段加载；界面测试检查正文可见及可滚动。构建 4 已于 2026-09-09 04:54（UTC+7）上传，因上述显示问题由构建 5 取代。构建 5 的上传和处理状态须独立确认。

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
3. 历史隐私政策曾发布于提交 6f80179077c60f3dbf37aafd0ef2832a775bdd50，当时匿名读取与包内文件一致。构建12的公开隐私说明应与包内2026-09-24版本一致，发布时须匿名核对公开URL与本地文件哈希。
4. 按实际第三方服务数据行为填写隐私标签。当前清单按账号关联的用户内容和账号识别信息声明应用功能用途、无追踪；服务商保留策略仍需核对，不默认填“未收集数据”。
5. 核验内置 iSH/Alpine 及修改源码的许可、源码提供与分发义务；明确说明解释执行、软件包与联网能力，按 Apple 对可执行代码和小程序/插件的实际适用要求准备审核说明。
6. 为新增 CLI OAuth 兼容路线确认客户端登记与分发权限，不把能握手称为厂商正式授权合作。
7. 使用当前二进制的真实截图与测试记录，完成 iPhone／iPad 真机前后台、取消、存储不足与网络切换验证。原生 iPad 新增侧栏、横竖屏、多任务尺寸和键盘布局须单独验收；模拟器用例通过不能关闭真机验收项。截图尺寸以 Apple 当前文档和后台要求为准。
8. 上传后等待 Apple 处理与审核；状态必须从后台核实。审核未通过或未发布时，不对外宣称上线。

## 官方参考

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- https://code.claude.com/docs/en/legal-and-compliance

## 源码发行记录

2026-09-09，源码分支 codex/release-readiness 已发布，提交 fdd26f55b2fe67ba42a3f3bd7d5ef813dd390b8a。对应源码与校验清单已公开于 [https://github.com/zhumingjie0223-cyber/Black-God/releases/tag/v1.2.0-build3](https://github.com/zhumingjie0223-cyber/Black-God/releases/tag/v1.2.0-build3)，标记为开发预发布。归档含 2,028 个文件及 Alpine 16 个包的 10 组源码，122 个上游 SHA-512 输入校验全部通过；5 项源码完整性测试通过。两个公开附件的 GitHub digest 与本地 SHA-256 完全相同。公开源码解决源码访问问题，不表示账号 API、真机验收或 App Review 已完成。

## 1.3.0（12）发行材料

对应源码（包含本轮UI/工具/存储修改、构建脚本和Alpine依赖源码）及逐文件校验清单：[v1.3.0-build12](https://github.com/zhumingjie0223-cyber/Black-God/releases/tag/v1.3.0-build12)。版本12使用本轮原生iPhone与iPad截图；审核说明见 `review_notes_20260924.txt`。真实模型账号联调和全面真机长跑仍未完成，既有模拟器与启动检查不替代这些结果。上传、处理、提交审核与正式上架必须分别记录。
