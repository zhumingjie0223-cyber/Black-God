# docs/ 目录索引

> 唯一索引（原 `INDEX.md` 已并入本页）。最后更新：2026-09-05（仓库大清洁：后端时代文档整体归档）。
> 状态：🟢 现行 ｜ 🟡 通用参考 ｜ 🔴 历史归档（只读，不再维护）

## 现状一句话

仓库只有两个 live 子系统：`ios-app/`（iOS 纯客户端 App）与 `shuyu/`（枢语引擎）。
原 Cloudflare Workers 后端 `web/nexus-do/` 已于 2026-09-05 删除，与之相关的规划/架构/部署/上架文档
**全部搬进 `archive/nexus-do后端时代-2026-09-05/`**，不再出现在下面的现行目录里。

## 现行与参考文档

| 目录 | 状态 | 内容 |
|---|---|---|
| [product/](product/) | 🟢 | `BLACK_GOD_NEXUS_CANONICAL.md`（产品唯一真相定义）、`ASI_GAP_AUDIT.md`（按当前 iOS 客户端盘点的 ASI 差距审计）、项目介绍、对外吸引方案、Logo 托管方案 |
| [spec/](spec/) | 🟢 | `CORE_PHILOSOPHY.md`（核心哲学）、`DESIGN_CHARTER_v2.md`（设计纲领）、神枢之道释义、设计参考总文档、Claude Agent 能力表、Review 提示词、28 工具规范 |
| [architecture/](architecture/) | 🟡 | 通用 Agent 内核理论：`AGENT_KERNEL_WHITEPAPER.md`、融合内核报告、四大 Agent 内核对标 |
| [design/](design/) | 🟡 | `nexus-autonomy.md`（自主意识构造方案，与 `shuyu/` 相关）、`UI_REDESIGN_ANALYSIS.md`、`DESIGN_SYSTEM_V3.md`（**未采用**的备选设计方向，非实现）、图标 |
| [api/](api/) | 🟡 | Claude Messages API 镜像、内部 API 笔记、核心提示词规范 |
| [done/](done/) | 🔴 | 已完成任务归档（TODO/PROGRESS 完工后进这里，按日期，不改写） |
| [archive/](archive/) | 🔴 | 历史归档，见下 |

## archive/ 结构

| 子目录 | 内容 |
|---|---|
| `nexus-do后端时代-2026-09-05/` | 后端删除时整体归档：`plan/`（全部旧计划与上线清单）、`architecture/`（Worker 架构与代码结构文档）、`product/`（旧 VPS/Worker 口径的"唯一真相"、数据总表、验收报告、Google Play 文案）、`上架/`（TWA/部署说明）、`shenshu/`、`web/`（旧 PWA 静态壳）、`skills/`、`ui-spec/`、`tools/`（旧推送脚本）、`env.example` |
| `server/` | 更早的 Python 服务端源码 |
| `handover/` `retrospective/` `planning/` | 交接、复盘、旧规划 |
| `ui-收口-2026-08-09/` 等 | 下线页面与孤儿脚本 |

## 阅读优先级

产品看 `product/BLACK_GOD_NEXUS_CANONICAL.md` → 差距看 `product/ASI_GAP_AUDIT.md` → 哲学看 `spec/CORE_PHILOSOPHY.md`。
iOS 上架材料不在这里，在 `ios-app/AppStore/`。设计令牌唯一权威源是 `ios-app/Theme.swift`。
