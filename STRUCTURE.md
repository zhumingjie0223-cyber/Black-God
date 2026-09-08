# Black God 仓库结构

> 当前发布入口是 `ios-app/BlackGodApp.swift`，工程定义为 `ios-app/project.yml`。
> 本说明依据当前原生 iOS 架构整理；历史资料中的 `web/nexus-do/` 已不在当前分支中。

## 原生应用与任务运行时

| 路径 | 作用 |
|---|---|
| `ios-app/BlackGodApp.swift` | SwiftUI 应用入口、全局状态和本地化入口 |
| `ios-app/RootView.swift`、`ChatView.swift` | 应用导航与对话界面 |
| `ios-app/ChatViewModel.swift` | 对话状态与请求协调 |
| `ios-app/NexusClient.swift`、`NexusModelBridge.swift` | 模型请求与响应桥接 |
| `ios-app/NexusModelCatalog.swift`、`NexusModelRouting.swift` | 模型目录和路由逻辑 |
| `ios-app/NexusRuntime.swift`、`NexusAgentLoop.swift` | 计划、运行事件与任务执行循环 |
| `ios-app/NexusTooling.swift`、`NexusExecutor.swift` | 工具注册、输入及执行接口 |
| `ios-app/NexusApproval.swift`、`NexusPermissions.swift` | 工具调用审批与权限判断 |
| `ios-app/NexusMemory.swift`、`NexusLocalTools.swift` | 本地记忆、检查点和文件工具 |
| `ios-app/NexusKeychain.swift` | 服务商密钥的 Keychain 存储 |
| `ios-app/Theme.swift` | 原生界面配色与公共样式 |
| `ios-app/zh-Hans.lproj/`、`ios-app/en.lproj/` | 简体中文与英文资源 |
| `ios-app/project.yml` | XcodeGen 工程定义、版本、标识符与资源列表 |
| `ios-app/BlackGod.xcodeproj/` | Xcode 工程，结构变更后按 `project.yml` 重新生成 |
| `ios-app/AppStore/` | 提交指南、商店文案、隐私政策与截图材料 |

客户端直接访问用户配置的模型服务商，不依赖自有 Cloudflare 后端。网络请求会将模型所需的对话和上下文发送给对应服务商；本地存储与第三方处理范围以当前隐私政策为准。

## 枢语引擎

| 路径 | 作用 |
|---|---|
| `shuyu/lexicon.js`、`shuyu/shuyu_engine.py` | v4.1 语义引擎的 JS / Python 实现 |
| `shuyu/lexicon_data.js` | 词族、情绪模板与能力词编号数据 |
| `shuyu/nexuslang.js`、`shuyu/gen.mjs` | 意识流解释器与状态生成逻辑 |
| `shuyu/worker.mjs` | 可选的 Cloudflare Worker 入口，独立于 iOS |
| `shuyu/tests/` | 引擎、解释器、Worker 与双实现测试 |
| `shuyu/docs/done/` | v4.1 能力变更与验证记录 |

本仓 v4.1 比独立 `shuyu-lang` 仓库的旧基线更新；统一版本应保留这些能力与测试。现有编号一致性校验不能替代全部导出接口、解释器和 Worker 的回归。原生工程未嵌入枢语 JS / Python 文件，也无需调用其 Worker 才能构建。

## 资产、文档与历史工具

| 路径 | 作用 |
|---|---|
| `web/`、`assets/` | 网页历史资产、品牌图标与媒体资产 |
| `ui-spec/` | 界面设计参考，当前实际样式以原生 `Theme.swift` 为准 |
| `android/` | 旧 Android 分发材料 |
| `docs/README.md`、`docs/INDEX.md` | 文档导航；其中历史状态需结合当前源码判断 |
| `docs/archive/` | 旧服务、页面、配置、Xcode 工程及历史资料 |
| `tools/`、`Makefile`、`.github/workflows/` | 开发和构建自动化，使用前确认目标为当前 iOS / 枢语路径 |

旧的 `web/nexus-do` 构建、DO 部署和网页双副本检查属于已退出当前运行路径的流程。当前应用构建和枢语测试命令见 [README.md](README.md)；正式上架见 [提交指南](ios-app/AppStore/SUBMIT_GUIDE.md)。
