# Black God AI · ASI 差距审计

## 结论

Black God 当前是**模型直连聊天客户端 + 枢语引擎基础 + 神枢状态骨架**，不是 ASI，也不是完整自主 Agent。距离“可验证的通用自主智能系统”仍缺少执行闭环、持久记忆、环境模型、评估体系和持续学习。

> ASI 没有公认可测的单一标尺。本文采用工程指标，不把“意识、情绪、词库容量”当作智能等级证明。

## 当前能力盘点

| 维度 | 当前状态 | 判断 |
|---|---|---|
| 多模型推理 | iOS 直连 Anthropic，支持模型选择与流式输出 | 已有基础 |
| 自主规划 | `NexusRuntime` 只有 `planning` 状态，未生成真实计划 | 缺核心 |
| 工具执行 | 枢语 `do` 可产出动作结构，但 iOS 未接 Tool Loop | 缺闭环 |
| 长期记忆 | 聊天历史本地保存设计存在，未形成可检索语义记忆 | 半成品 |
| 工作记忆 | 当前以消息数组传递 | 基础可用 |
| 反思验证 | 没有独立 verifier、测试判据和自动重规划 | 缺核心 |
| 世界模型 | 没有实体、时间、因果、状态和不确定性模型 | 缺失 |
| 持续学习 | 有枢语状态/词库，但没有从结果中安全更新策略的管线 | 缺失 |
| 多 Agent 协作 | 仅有文档/历史设计，当前 iOS 未实现 | 缺失 |
| 可靠性 | 基础错误回调；缺幂等、断点恢复、预算和回滚 | 不足 |
| 自主性 | 没有后台目标、触发器、权限和审批系统 | 缺失 |
| 评测 | 枢语回归测试 48 项通过；没有任务成功率基准 | 不足 |
| 资源闭环 | 没有模型成本、时间、工具风险的统一调度器 | 缺失 |

## 离 ASI 最近的升级顺序

### P0：完成 Agent 闭环

把 `NexusRuntime` 从状态展示升级为真正运行时：

```text
parse → plan → execute → observe → verify → replan → deliver
```

需要的数据结构：`TaskPlan`、`TaskStep`、`ToolCall`、`Observation`、`Verdict`、`Artifact`、`RunCheckpoint`。

验收：给定 20 个跨步骤任务，成功完成率、工具错误恢复率、最终交付率可自动统计。

### P1：本地工具总线

统一 Swift 工具协议：

```text
Tool.name
Tool.inputSchema
Tool.execute()
Tool.permission
Tool.rollback()
```

首批接入：文件读写、Apple 原生能力、iSH 命令、网页抓取、媒体处理。所有工具必须有超时、取消、日志和权限门。

### P2：可检索长期记忆

分成四层：

```text
working memory / episodic memory / semantic memory / user preferences
```

每条记忆带来源、时间、置信度、过期策略和删除接口；检索结果必须可解释，不能把模型猜测写成事实。

### P3：世界状态与任务恢复

建立实体-关系-事件模型，记录文件、项目、任务、设备、时间和外部结果。每步保存 checkpoint，应用被杀后可以恢复、回滚或安全重试。

### P4：验证与自我纠错

每个任务必须有验收标准；独立 verifier 检查：结构、事实、测试、文件产物和副作用。失败后只允许在预算内重规划，超过预算转人工确认。

### P5：能力学习而非人格膨胀

将成功轨迹抽象成技能模板，把失败归因到工具、计划、知识或环境；技能版本化、沙箱测试、灰度启用、可回滚。不要把“情绪、人格、意识流、词库容量”当作学习证明。

### P6：规模化通用能力

再考虑多 Agent、跨设备、后台触发和更大模型。先用基准证明单 Agent 在陌生任务上的迁移能力，再扩规模。

## 建议核心指标

```text
Task Success Rate
First-Pass Success Rate
Recovery Rate
Plan Validity Rate
Tool Failure Rate
Verification Precision
Hallucination Rate
Checkpoint Recovery Rate
Cost per Successful Task
Latency per Successful Task
Permission Violation Rate = 0
```

## 现实距离判断

- 距离“能聊天的 AI”：已达到。
- 距离“可用自主 Agent”：约完成 20%～30%，主要缺执行闭环。
- 距离“可靠通用 Agent”：约 10%～15%，主要缺验证、记忆、环境模型和恢复机制。
- 距离 ASI：无法用代码行数或词库容量估算；当前尚未具备可称为 ASI 的工程证据。

## 最重要的判断

Black God 的升级方向不是继续堆“意识、灵魂、人格、词库”，而是把每个目标变成可执行、可观察、可验证、可恢复的闭环。先做到陌生任务稳定完成，再谈更高层级智能。
