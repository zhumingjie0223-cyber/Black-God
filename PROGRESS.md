# PROGRESS · 私人版全面强化「全部都要」分波实施

分支：`claude/black-god-enhancement-plan-6gc2pw` · PR #86
底本：`web/nexus-do/nexus_do.core.mjs`（4644 行生产级 DO，跑在 aquan.lufei.uk）
方案全文：`docs/私人版全面强化方案-2026-07-28.md`（六轴 22 项 + 竞品对标三新增轴）

## 已完成（已推送 PR #86）

- [x] **方案文档**：六轴 22 项，落到方法名/接口/数据结构 + 竞品对标附录（13 家逆向消化）
- [x] **第一波 · 记忆真 bug 修复**（commit 7e05221）
  - `_embed` 英文 `bge-base-en-v1.5`(768维) → 多语 `bge-m3`(1024维)，中文召回质量翻倍
  - 每条向量打 `_vec_model` 标记；维度不符靠 `_cosine` 长度守卫天然隔离，向后兼容
  - 新增 `reembedMemories(soul,limit=5)`，心跳里分批重嵌旧向量，落盘后跑、best-effort
  - 自测：`node build.mjs` + `selftest` 228/228 通过；capsec 37 项、apple/continuity 全过
  - 注：gateway 的 `_auto_model` 缓存那条为**既有失败**（stash 对比确认），与本改动无关

## 后续分波（按优先级，每波：改 core → `node build.mjs && node selftest.mjs` → 独立提交）

### 第二波 · 具身×自主打通（4.1，P0，纯代码可自测）
- `execAgentTask` 动作集加 `ios`：`{action:'ios',args:{tool,params}}` → 路由到 `handleAgent` 工具执行层
- iOS 动作走「意图入队 + 设备拉取执行 + 回执」异步模型，该步先 `pending`，收回执再 `done`
- 落点：`execAgentTask` 的 `validActions` 数组 + switch；`handleAgent` 抽出工具执行子函数复用

### 第三波 · agent 反哺技能/教训（5.1，P0，可借现成 skillUpsert 测试）
- 成功 `finish(verified)` → `skillFromAgentRun(run)` 炼 `来源:'实战'` 技能喂 `skillUpsert`
- 失败 → `lessonFromFailure(run)` 写 `soul.教训=[{topic,反模式,后果,ts,强度}]`
- `execAgentTask` 起手把相关教训注入 systemPrompt（复刻 `skillRetrieve` 召回逻辑）

### 第四波 · grounding 依据链（第九轴，P2，纯增强低风险）
- 统一结果加 `依据:{基于:[],验证:null,来源:[]}`；`handleTalk` 联网/召回/调能力时填充
- 前端回答/执行卡片折叠展示（玉绿令牌，只读）

### 第五波 · 显著性引擎（2.1，P0，纯函数可测）
- `salienceScore(event,soul)` = 变化幅度 × 主题重要度 × 画像相关度 × 时段合适度
- `runOneDueLoop` 的 `change` 策略过 `≥阈值` 闸；`distillNotifyPref` 从 `proactive_log` 回执学 `soul.打扰阈值`

### 第六波 · Plan/Act 双模式（第八轴，P1）
- `execAgentTask` 加 `mode:'plan|act'`；`plan` 只产 `{steps,risks,预估}` 存 `agent_run.plan` 不执行写/命令
- 命中「重构/迁移/部署/删除」或预估步数 >3 自动进 plan；复用 `/api/confirm` 转 act

### 第七波 · 跨心跳续跑状态机（1.1，P0，**最大重构、最需谨慎、务必真测**）
- `execAgentTask` 循环体拆成可持久化 `agentStepper`，每步落 `agent_run:<id>`
- `autonomousTick` 加 `advanceDueAgentRuns()` 每分钟推进 running 任务各一步（budget 200步/24h）
- 完成走 `execPushResult` 推回；接口 `POST/GET /agent/run`
- ⚠️ 碰核心执行循环，改前先把现有 `execAgentTask` 行为用例固化，逐步替换不一次性重写

### 第八波 · MCP 动态工具扩展（第七轴，P1，新模块）
- `mcp_servers` 存储 + `loadMcpTools()`（拉 remote MCP over HTTP/SSE 的 tools/list）
- 注入 `execAgentTask` 动作集（`mcp_<server>_<tool>` 前缀）；`callMcpTool` JSON-RPC 转发 + 分级确认
- 接口 `POST /mcp {action:'add|remove|list|probe'}`

### 第九波 · 需新增 CF 绑定（1.2 R2 快照 / 3.2 Vectorize 外置）
- 先写代码 + wrangler 配置 + **未绑定优雅兜底**（退回现有 clone/内联余弦，不炸）
- R2 `WS_SNAP`：`execWorkspaceSnapshot/Restore`（堵容器 sleepAfter=10m 的 /tmp 丢失）
- Vectorize `MEM_VEC`(1024维对齐 bge-m3)：`retrieveMemoriesSemantic` 改走 `MEM_VEC.query`
- ⚠️ 实际 bucket/index 需权哥在 CF 侧 provision（或授权我用 CF MCP 工具建），代码先备好

### 收尾波 · 界面（6.1 执行剧场 / 6.2 记忆图谱·成长仪表盘，P1/P2）
- `agentStepper` 每步 `broadcast({type:'agent_step',...})`；前端加执行剧场面板
- 严守设计铁律：只用页内 `--cy-*`/`--chrome-*`/`--live` 玉绿令牌，动效仅 transform/opacity

## 红线（每波继承，不可破）
`/api/confirm` 二次确认、`dangerReason` 危险门、`OWNER_TOKEN` 鉴权、多租户系统专属路由隔离；
不碰枢语引擎词根表/编码空间（那是跨仓一致性红线，需 sync-auditor）。

## 恢复指引
接着干时：读本文件 → 从「第二波」起，逐波改 core、`node build.mjs && node selftest.mjs` 自测、独立 commit 推 PR #86。
