# 意图与证据回归检查

在仓库根目录运行：

```sh
tools/intelligence/run-tests.sh
```

脚本编译真实的 `ios-app` 聊天与快捷指令入口、意图编译、情节召回、认知治理账本、证据复核、推理、执行器、工具注册表、只读联网与原生协议源文件；所有生产源码逐字复制到临时 SwiftPM 目录，测试只替换模块导入。临时目录随退出删除。它执行固定中文意图集、入口恢复与澄清、会话隔离、核心 XCTest、原生与文本工具边界以及真实执行器的复核与检查点回归，结果由断言和工具证据判定。联网测试使用内存响应和 URLProtocol 夹具，不访问外网。

`Support/PlatformSupport.swift` 提供系统密钥链、默认模型、模型网络客户端和 iSH 运行时适配器，以及从生产源码复制的消息与工作区路径数据声明。适配器不发起服务商请求、不执行 iSH；测试显式注入模型、工具、凭据夹具及文件操作。被测的聊天与快捷指令入口、认知账本与持续状态存储、编译、召回、记忆/技能存储、情节、证据、安全门、推理、执行器、注册表、原生工具协议、路由/发送许可、事务备份/恢复、会话库和保险库使用真实应用源码。沙箱工具清单也来自真实 `NexusSandboxTools.swift`，没有伪注册不存在的生产工具。

Linux 的 `Combine` 测试模块提供数据包装和不发送事件的订阅名称声明；`SwiftUI` 模块仅重导 Foundation/Combine，让不含界面绘制的真实 `ChatViewModel` 编译，不实现任何视图。测试不验证订阅通知、界面绘制或属性生命周期。`JavaScriptCore` 声明适配器让真实枢语包装编译，初始化始终失败，不伪造枢语结果；旧版下载工具使用的 `URLSession.bytes(for:)` 在 Linux 也明确拒绝执行。`CryptoKit` 测试模块的 SHA-256 API 调用已安装的 OpenSSL，并通过公开的空字符串与 `abc` 已知摘要验证；不伪造摘要或跳过摘要核对。Ubuntu/Debian 需预装 `libssl-dev` 和 `pkg-config`，安装脚本会在下载 Swift 前检查它们，没有其他 Swift 包依赖。macOS 使用系统的 Combine/CryptoKit/SwiftUI/JavaScriptCore。

会话存储与保险库也直接编译真实源文件；清空回归先创建实际会话和旧版情节文件，再检查删除结果与记忆/技能保留。`NexusSessionLibraryTests` 六项原断言都执行，包括真实聊天入口的切换、导出与隔离；`NexusChatRecoveryTests` 检查中断恢复不会补出命令授权；`NexusTaskServiceIntentTests` 检查快捷指令澄清、来源和连接隔离，情节夹具必须经真实 `record` 与 `load` 核对。

环境没有 Swift 时，在 x86_64 Linux 运行：

```sh
tools/intelligence/install-swift-linux.sh
```

默认下载位置为 `/workspace/.toolchains`，可用 `BLACK_GOD_TOOLCHAIN_ROOT` 修改；可用 `SWIFT_BINARY` 指定已有 Swift。下载固定为 Swift 6.2.1 Ubuntu 24.04 官方发行，先验证官方 GPG 签名、公钥指纹及固定 SHA-256，再解压。公钥从官方 `swiftlang/swift-org-website` 固定提交获得，保留 TLS 验证。发行于 2025 年 11 月签名，早于签名公钥 2026 年 9 月到期；GPG 会报告现时到期警告，同时验证历史签名。Debian 13 本环境已实际验证该工具链可运行。

默认并行编译 4 个任务，可用 `SWIFT_TEST_JOBS` 调整。测试不需要模型密钥、外部服务或执行 shell 工具，工具调用均使用本地测试夹具。缓存也放在临时目录，不写用户主目录。Apple `NaturalLanguage` 的系统语义向量不可在 Linux 验证，测试可注入固定向量验证召回行为。完整 SwiftUI/iOS 链接、界面、Combine 订阅、JavaScriptCore 枢语运行、系统向量可用性和设备运行仍须 macOS/Xcode。
