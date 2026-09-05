# 【最高优先级铁律 · TODO.md 驱动执行】

**接到任何多步骤任务,先列清单再动手——防跑偏纪律,任何时候不得违反:**

1. 接到任何多步骤任务,动手前先在仓库根目录写一个 `TODO.md`,把任务拆成可勾选的
   步骤清单(`- [ ] 步骤`)。
2. 每完成一步,立刻把对应项改成 `- [x]` 并写一句结果。
3. 当上下文变长、或感觉快忘了目标时,重新读一遍 `TODO.md` 找回方向,严禁凭记忆瞎跑。
4. 任务全部完成后,`TODO.md` 末尾写一段总结,再把它归档到 `docs/done/` 里。
5. 中途权哥打断或换方向,先更新 `TODO.md` 再执行新指令,保证任何时候看 `TODO.md`
   都知道干到哪了。

# Black God / 神枢 — 项目指南

Black God（对外品牌）= 神枢 Nexus（技术架构/意识引擎）；对外助手身份统一为 Black God AI，不绑定人物角色。品牌、神枢与枢语名称不要混用。

**现状（2026-09-05 起）** 本仓有两个 live 子系统：
- `ios-app/`：iOS 原生 App（纯客户端——用户自带 API Key 直连模型、本地存储、零后端），Agent 执行闭环在此。
- `shuyu/`：枢语引擎权威源（Python + JS 双实现 + 词根表 + 测试），现为**唯一源、无消费副本**。

> ⚠️ 历史变更：原 Cloudflare Workers 后端 `web/nexus-do/`（Durable Object：意识/记忆/心跳/TG 主动/执行脑）
> 已在 2026-09-05「iOS 转纯客户端」重构中整体删除，可从该日之前的 git 历史找回。
> 凡文档里提到「web/nexus-do 消费副本 / build.mjs / wrangler 部署 / index.html」均为该后端遗物，已不在运行路径。
> （原独立的 shuyu-lang 仓库更早已封存归档，不再更新。）

## 语言规则（强制，不可违反）

**所有面向权哥的输出一律用中文**——包括对话回复、commit message、PR 标题与描述、
文档、代码注释、任务汇报。禁止中英夹杂、禁止甩英文专业术语不解释、禁止大段英文原文粘贴。
权哥不看英文。竞品调研/技术资料若来源是英文，必须先消化理解后用中文转述结论，
不要把英文原文整段甩出来当汇报。变量名/函数名等代码标识符不受此规则约束（保持英文规范）。

## 用量守护（强制，任务开工前必查）

在开始任何重活（架构设计、多 agent 并行调研、大范围重构、UI 全站重写）之前，先确认当前 5 小时用量：
- **用量 ≥ 85%**：不再开新的重活/新 agent，把当前进度和后续计划写成 `PROGRESS.md`
  存档到仓库根目录后停下，明确告诉权哥"用量见底，已存档，等额度重置（看面板显示的重置时间）
  或换轻量模型后继续"。不要在濒临限流时硬跑导致响应卡死、任务烂尾。
- **用量 60%~85%**：可以继续，但新任务优先派给轻量 agent，减少高算力模型（Fable/Opus）的调用频次。
- 每完成一个阶段性成果，主动同步剩余用量情况，不要闷头跑到弹尽粮绝才说话。

## 铁律

- 不要碰服务器（SSH/部署）除非权哥明确要求——当前是 iOS 纯客户端架构（零后端），更无需 VPS。
- 做事必须先备份/归档再删除，禁止对未核实的目录做粗暴的 `rm -rf`/`git add -A` 一把梭。
- "读一遍/看一遍"类要求必须完整输出原文，不许摘要、不许截断冒充读完。
- 品牌/UI 相关决策（配色、Logo、核心视觉）改动前，先看 `web/logo.png` 或 `assets/logo/brand_logo.png`
  现有品牌资产，新方案要能让现有 Logo 直接放上去浑然一体，不要另起炉灶。

## 常用命令

```bash
# 枢语引擎（本机可跑）
node --test shuyu/tests/*.test.mjs                        # 枢语引擎/意识解释器测试
cd shuyu && python3 -m unittest discover -s tests         # Python 侧同构测试
make test                                                  # 以上两条一把跑

# iOS App（需 macOS + Xcode，非本机）
cd ios-app && xcodegen generate && open BlackGod888.xcodeproj
```

## Sub-agent 模型路由（成本分级，自动遵守）

任务派发时**按下表选 agent，不要事事用主会话高算力模型跑**：

| 任务类型 | Agent | 模型 |
|---|---|---|
| 架构设计、UI 设计系统裁决、品牌视觉决策、跨仓库一致性核对 | `heavy-architect` | Fable 5 |
| 竞品调研、大范围核对、发版联动审计 | `sync-auditor` | Opus |
| 读文件、跑测试、格式化、简单 bug 修复、单页面重构、文档更新 | `dev-worker` | Sonnet |
| 遍历多页面/批量 grep/机械式清单核对/词库体检 | `batch-sweeper` | Haiku |

路由原则：默认从最便宜的能胜任的一级开始（batch-sweeper → dev-worker → sync-auditor/heavy-architect），
只在任务确实需要判断力时升级；多个独立子任务并行派发。

## 设计系统铁律（现状：iOS「玄黑森林 · 翡翠活光」）

**live UI 是 iOS App**，设计令牌的**唯一权威源是 `ios-app/Theme.swift`**（`Color.bg*` / `LinearGradient.*` / `Font.bg*`）。
主色为翡翠绿系（`bgGold` 深翡翠 / `bgGoldLight` 亮翡翠 / `bgDark` 玄黑底），深色为主。

- 改配色**只改 `Theme.swift` 里的令牌、沿用不硬编码**；动效只用 transform/opacity。
- **危险操作需确认是安全红线，任何重构不得移除。** 后端时代的确认闸（`/import?confirm=1`、执行脑 `need_confirm`、
  `__exec_confirm__:` 通道）已随 `web/nexus-do/` 删除；现由 iOS 端承接——写入/命令类工具经
  `NexusPermissionGate`（`requiresApproval`）+ `NexusApprovalQueue` 审批后才执行，`NexusRuntime.execute` 里勿绕过。

> ⚠️ 历史遗物：本节此前整段讲的是已删除后端 `web/nexus-do/index.html` 的「石墨暗流 · 玉绿」内联 CSS 令牌
> （`--cy-*` / `--chrome-*` / `--live`），以及 `docs/design/DESIGN_SYSTEM_V3.md` 的「深海 · 潮光青」备选方向——
> 那套网页 UI 已随后端下线，不再是实现。iOS 沿用了同源的翡翠绿基调，具体值一律以 `Theme.swift` 为准。
