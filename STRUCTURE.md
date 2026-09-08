# Black God 仓库结构

> 当前发布入口是 `ios-app/BlackGod888App.swift`，工程定义为 `ios-app/project.yml`。
> 本说明依据当前原生 iOS 架构整理；历史资料中的 `web/nexus-do/` 已不在当前分支中。

## 原生应用与任务运行时

| 路径 | 作用 |
|---|---|
| `ios-app/BlackGod888App.swift` | SwiftUI 应用入口、全局状态和本地化入口 |
| `ios-app/RootView.swift`、`ChatView.swift` | 应用导航与对话界面 |
| `ios-app/ChatViewModel.swift` | 全应用共享任务状态；通过 onUpdate 显示计划并保存检查点，协调停止、恢复与历史保存 |
| `ios-app/ToolsView.swift`、`ios-app/MonitorView.swift` | 工作台、本机时钟/计算器、最近 50 次任务历史与详情 |
| `ios-app/NexusClient.swift`、`NexusModelBridge.swift` | 模型请求与响应桥接 |
| `ios-app/NexusModelCatalog.swift`、`NexusModelRouting.swift` | 模型目录和路由逻辑 |
| `ios-app/NexusPlanning.swift`、`ios-app/NexusExecutor.swift` | 模型计划、逐步执行、工具结果回传与检查点恢复 |
| `ios-app/NexusVerifier.swift` | 输出完整性与格式检查；不验证事实或任务成功 |
| `ios-app/NexusRuntime.swift`、`NexusAgentLoop.swift` | 保留的其他运行时组件，当前对话主链由 ChatViewModel 调用 NexusExecutor |
| `ios-app/NexusTooling.swift`、`NexusExecutor.swift` | 工具注册、输入及执行接口 |
| `ios-app/NexusApproval.swift`、`NexusPermissions.swift` | 工具调用审批与权限判断 |
| `ios-app/NexusMemory.swift`、`ios-app/NexusMemoryView.swift` | 用户手动收藏/添加的记忆：最多 200 条、每条 4000 字；中英文检索与管理 |
| `ios-app/NexusTaskHistory.swift` | 最多 50 次任务：模型、计划、工具记录、结果及完成/失败/取消状态 |
| `ios-app/NexusEvaluation.swift`、`ios-app/NexusDataReset.swift` | 兼容旧评估记录；汇总清除文件和钥匙串的失败信息 |
| `ios-app/NexusLocalTools.swift` | 检查点持久化及保留的文件工具定义；文件工具不属于默认任务工具集 |
| `ios-app/NexusKeychain.swift` | 服务商密钥的 Keychain 存储 |
| `ios-app/Theme.swift` | 原生界面配色与公共样式 |
| `ios-app/zh-Hans.lproj/`、`ios-app/en.lproj/` | 简体中文与英文资源 |
| `ios-app/project.yml` | XcodeGen 工程定义、版本、标识符与资源列表 |
| `ios-app/BlackGod888.xcodeproj/` | Xcode 工程，结构变更后按 `project.yml` 重新生成 |
| `ios-app/AppStore/` | 提交指南、商店文案、隐私政策与截图材料 |

默认任务工具仅有时钟、受限计算和原样文本回传，没有网页检索、shell 或手机系统控制。记忆必须由用户主动收藏，格式检查不得称作事实验证。

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
| `tests/run_ios_runtime_tests.sh` | 原生计划、执行器、解析器、停止/恢复及响应桥接回归 |
| `ios-app/StorageTests/run.sh` | 编译真实存储源码，在临时目录测试；隔离钥匙串与其他外部边界 |
| `Makefile` | 当前 iOS 无签名构建、原生测试和枢语双实现测试 |
| `.github/workflows/build.yml` | 手动触发的 iOS 回归与无签名编译检查，不上传 App Store |
| `tools/`、其他 `.github/workflows/` | 历史工具与独立工作流；旧网页部署不属于本次 iOS 发布 |

旧的 `web/nexus-do` 构建、DO 部署和网页双副本检查属于已退出当前运行路径的流程。当前应用构建和枢语测试命令见 [README.md](README.md)；正式上架见 [提交指南](ios-app/AppStore/SUBMIT_GUIDE.md)。
