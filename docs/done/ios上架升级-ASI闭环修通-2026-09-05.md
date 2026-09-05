# TODO — iOS 上架升级 v1.1.0（ASI 闭环修通 + App Store 合规）

> 目标：把 iOS App 修到能编译、能上架、ASI 执行闭环真跑通。分支 `cursor/ios-asi-upgrade-96d7`。
> 决策默认（用户跳过选择，取推荐项）：合规内容做替换、ASI 做务实修通 P0–P4、版本升 1.1.0 / build 2。

## A. 修编译（最高优先级：main 当前编译不过）
- [x] A1. 统一工具协议：`NexusToolRegistry` 改引用类型（class），补 `tool(named:)/manifest/isEmpty/allTools`；`NexusTool` 加 `usage`（默认空实现），统一到 `execute(_ call:) async -> NexusToolResult`
- [x] A2. 内置工具 `NexusClockTool`/`NexusCalculatorTool` 改为符合统一协议（读 `call.arguments`）；用安全递归下降求值器替换会崩的 NSExpression
- [x] A3. `NexusExecutor` 改用统一注册表与结构化结果；修 executeTool 类型不匹配；修 `isAtEnd` 用 `mutating get`（Swift 编译器实测抓到）
- [x] A4. `NexusExecutionLoop` 去掉多余 mutating，配合 class 注册表
- [x] A5. 全仓 grep 核对无残留旧协议调用（run(arguments/NexusExternalModels/nativeModel 均清零）

## B. ASI 闭环真跑通（P0–P4）
- [x] B1. 修「prompt 约定 ↔ 解析器」不一致：统一 ```tool JSON 约定 + 重写 `NexusToolCallParser`（含 stripCalls / 多块 / 松散 JSON）
- [x] B2. Executor 单步多轮工具闭环端到端可用（clock/calc/echo 只读安全工具，Swift 包实测跑通）
- [x] B3. 模型目录归一：`NexusModelCatalog` 作唯一来源，`APIConfigView`/`NexusClient`/`NexusModelRegistry` 全部引用；去掉可疑第三方转售条目（apiclaude.cc/gpt-6-astra）
- [x] B4. APIConfigView 按所选模型的 provider 存 Key；NexusModelRegistry 读/写 Keychain；请求体不下发原生工具 schema（文本闭环不断裂）

## C. App Store 合规（替换法）
- [x] C1. ToolsView：移除渗透/C2/免杀/破解等黑客工具，改为展示执行闭环与工具总线
- [x] C2. MediaView：含 NSFW/人物向文案且无功能 → 下线该 Tab（enum/RootView/TabBar/删文件 同步）
- [x] C3. MeView：去人物向文案（888专属/甜美语音/助手模式），「Cloudflare」改直连，版本号动态取
- [x] C4. ChatView：移除无功能麦克风；电话按钮改为可用的「API 配置」入口
- [x] C5. project.yml：移除已不用的麦克风/相册权限；版本 1.0.0→1.1.0，build 1→2
- [x] C6. 版本发布说明 release_notes（中英）+ 截图模型列表对齐新目录

## D. 测试与验证
- [x] D1. Linux 装 Swift 6.3.3，把 Foundation-only 核心搭成 /tmp SPM 包 → 编译通过 + 29 项断言全绿
- [x] D2. 扩充 `NexusCoreTests`（App DEBUG 自测）覆盖工具协议/注册表/解析器/验证器/模型路由/终止策略/Executor
- [ ] D3. 逐项提交 + 推送 + 建 PR（draft）

## 结论
（完工后补总结，归档到 docs/done/）
