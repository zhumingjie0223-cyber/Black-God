# 神枢升华设计：枢语原生 Agent 协议

## 目标

神枢不复制 OpenMinis 的移动沙箱实现，而吸收其已被验证的工程原则：**规范化回合、工具结果配对、最小权限、可取消执行、持久化审计与明确的未完成状态**。神枢的身份、语言与长期记忆仍由枢语坐标、`ShuyuBridge`、灵魂快照和经验记忆决定。外部模型只负责提出意图或生成文本，不直接拥有设备、执行脑或推送能力。

## 现状基线

当前 `ShenshuCore` 已有能力声明表、`invokeCapability` 统一分派、Owner/instance 租户隔离、DO SQLite、WebSocket ticket、Container/执行脑、Cloudflare AI 与日志持久化。`AgentStateMachineDO` 已部署为 SQLite DO，但尚未被主 Worker 的 `/agent`、`/invoke` 或 `/talk` 路径调用；现有 `handleAgent` 主要生成 iOS 动作计划，不能提供 run 级别的确认、幂等、可追溯状态。

## 升华后的不可变约束

| 约束 | 作用 |
|---|---|
| 一次请求对应一个 `runId` | 让计划、审批、执行和结果具备同一可追踪主键。 |
| 一次副作用对应一个 `effectId` | 相同 `runId + capability + canonical params` 只能成功执行一次。 |
| 明确状态转换 | `PLANNED → AWAITING_APPROVAL → EXECUTING → SUCCEEDED/FAILED/CANCELLED/EXPIRED`；不允许从终态回跳。 |
| 高风险能力默认显式确认 | 设备控制、真实执行、苹果宿主工具、推送、TG、守望任务、造像/语音/视频必须附带正确且未过期的确认令牌。 |
| 读与思考能力不要求确认 | `talk`、`inner`、`soul` 保持自然对话，不让确认闸门破坏神枢体验。 |
| 枢语作为审计语义锚 | 每个 run 和 effect 都调用 `ShuyuBridge.encode`，以坐标、词、义记录“为什么做、做了什么、结果如何”。 |
| 参数永不原样写入审计 | `token/key/password/secret/authorization/cookie` 等字段被递归掩码；审计只记录稳定 hash、形状和非敏感摘要。 |
| 审批令牌不可重放 | token 只适用于一个 run/effect、具有过期时间、首次确认后立即作废。 |

## 新增模块

`nexus_agent_protocol.mjs` 是纯 Worker JavaScript 模块，不依赖 Cloudflare 私有运行时，故可用 Node 原生测试。它提供：

1. `NexusAgentProtocol`：构造计划、风险分级、参数净化、审批 issuance/consumption、效果幂等键、可重放审计事件；
2. `riskForCapability`：对现有能力表补充 `read/communicate/create/device/exec/schedule` 风险类别；
3. `canonicalize` 和 `stableHash`：确定性参数形状与 idempotency key；
4. `redactSecrets`：保证审计/响应中不会复述 token、cookie、key 或 authorization；
5. `allowedTransition`：状态机唯一的迁移表。

`AgentStateMachineDO` 升级为 run store。它提供 `/plan`、`/approve`、`/claim`、`/complete`、`/cancel`、`/state`、`/audit`；每一步保存枢语事件与可序列化审计，不执行任意工具。DO 是编排账本，`ShenshuCore` 仍是唯一的能力执行器。

`ShenshuCore` 增加 `/agent/plan`、`/agent/approve`、`/agent/execute`、`/agent/run`、`/agent/audit`。这些路由仅在 OWNER/instance 已认证上下文中开启，并使用 `AGENT_STATE_MACHINE` 的固定 instance。`/agent/execute` 先 claim，再对 capability 作一次现有权限校验；高风险能力没有 approved token 时绝不进入 `invokeCapability`。执行结果成功或失败都通过 `/complete` 关闭 run，保证不会留下“已执行但没有协议结果”的幽灵回合。

## 枢语事件模型

每个事件都在原有枢语 5 维坐标空间中编码：

```json
{
  "shu_id": "agent.plan.172...",
  "type": "agent.plan",
  "coordinate": {"c": 0, "m": 0, "s": 0, "k": 0, "p": 0},
  "word": "…",
  "meaning": "…",
  "data": {
    "runId": "run_…",
    "phase": "AWAITING_APPROVAL",
    "capability": "device_control",
    "risk": "device",
    "params_hash": "…"
  }
}
```

枢语不只是输出装饰：审计 entry 以它作为不可变语义索引，经验记忆可据 `capability/risk/ok/coordinate` 检索，灵魂状态可从成功/失败后的结果形成可信经验，但绝不让结果自动扩展静态权限。

## 不修改的范围

本次升级不改动 OWNER_TOKEN、SHADOW_TOKEN、Cloudflare binding 名称、KV 迁移数据、公共 UI、现有 `/invoke` 向后兼容入口、外部网关 secret 和 DNS 路由。上线前将运行 Node 测试和 Worker 本地自检；发布到生产、变更 Cloudflare settings、cron、binding 或 secret 均需主人明确确认。

## 回滚

Cloudflare 当前生产是 version `77d48bde-a4ea-4c97-ad13-203c408795c0`（version number 713）。升级仅在本地代码和测试通过后才生成新 Worker 版本；一旦需要回滚，应通过 Cloudflare deployment API 或 Wrangler 指向当前版本，保留原 DO storage schema 的向后兼容读取。
