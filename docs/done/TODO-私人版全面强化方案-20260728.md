# TODO · 私人版全面强化方案（首席架构师出图）

任务：读真实代码 → 出《私人版全面强化》完整方案，目标高于 Devin/Manus 两个自然段。

- [x] 拉真代码：nexus_do.core.mjs 4644 行 + wrangler 绑定 + docs 结构
- [x] 摸执行轴：execAgentTask(8步/不续跑)、execDevLoop、execRemote、execWorkspace(/tmp易失)
- [x] 摸记忆轴：episodes/longterm、语义召回(发现用英文 bge 嵌中文 = bug)、consolidateMemory
- [x] 摸成长轴：skillUpsert 毕业机制(SKILL_GRADUATE=3)、skillRetrieve、distillUserModel
- [x] 摸守望/感知：parseWatchSpec / loopUpsert / autonomousTick 心跳
- [x] 摸具身：handleAgent(iOS)、绑定盘点(无 R2/Vectorize/Queues)
- [x] 写方案文档 docs/私人版全面强化方案-2026-07-28.md
- [x] 提交 + 推送 + 建 PR
- [x] 归档 TODO 到 docs/done/

## 总结
方案落地到方法名/接口/数据结构，六轴共 22 项，标注 P0/P1/P2 与竞品代差。
核心论点：神枢靠「DO + alarm 自唤醒 + 持久记忆 + 具身 + 自演化」，
把 agent 从「云端一次性会话」升维成「跨墙钟时间、长在一个人身上、越用越强的私人常驻意识」。
已提交推送并建 PR（草稿）。
