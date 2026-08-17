# OpenMinis→神枢全域能力映射与整合基线

**审计日期：**2026-08-17  
**OpenMinis 源码基线：**`9cf3a855fecd27bb5735b84cacbd56852a3ab8dd`  
**神枢仓库基线：**`Black-God/main`，当前已推送版本 `92e8fe8`  
**目的：**本文件不是功能愿望列表。它将 OpenMinis 已经核实到函数、协议帧、持久化和构建链的能力，与神枢仓库中的真实调用链逐项对照，作为后续改造、实测和发布的唯一验收基线。

> **核心结论：**神枢已经拥有较强的 Cloudflare 中枢、枢语语义、Container 浏览器、内置 Shell、设备中继、Durable Object 账本和 Web 入口；但其关键能力仍分散在多套模块中。要达到 OpenMinis 级别的完整 Agent 产品，必须把“文本标记式的五轮循环”“薄 iOS OpenAI 客户端”“无 MCP/OAuth 运行面”和“缺少移动 Linux 根文件系统”的分散实现，收敛为一条可恢复、可审计、可实测的统一运行链。

## 1. 能力地图总览

| OpenMinis 已核实层 | 关键证据 | 神枢现有真实能力 | 当前判定 | 必须完成的神枢整合 |
|---|---|---|---|---|
| Agent 回合状态机 | `AIChatViewModel` 维护 `agentHistory`、UI 派生消息、原始 DB 回合；最多 200 轮；工具结果按原顺序回灌 | `ShenshuCore.runAgentLoop()` 最多 5 轮，解析 `⟨工具:...｜...⟩` 文本标记；`AgentStateMachineDO` 已有 plan/approval/lease/run/audit | **部分实现，尚未统一** | 让所有 Agent 工具回合使用同一个 DO run ledger、typed tool call、持久化 history 和可恢复状态；弃用将工具调用仅编码在文本中的核心依赖 |
| 工具并发与回灌完整性 | OpenMinis 固定上限 10 并发、source-index 排序、成对持久化 tool use/result | 神枢每轮最多截取 2 个 call，按 `for...of` 串行执行；工具日志为内存数组后回给模型 | **明显缺口** | 引入有界并发执行器、稳定 `tool_call_id`、原顺序重组、已完成配对不可丢失、取消时可恢复 |
| 流式 Provider 协议 | OpenAI Chat/Responses、Anthropic、Gemini 统一为 `AgentStreamEvent`；SSE 处理 usage、reasoning、tool JSON delta | `brainProvider/buildBrainReq/parseBrainText` 支持 OpenAI/Anthropic/Gemini 的非流式单轮文本请求 | **明显缺口** | 新建 Provider Adapter 层，支持流式事件、Responses API、typed function call、reasoning 回放、token/finish 原因和 provider-specific ID 规范化 |
| 工具输入预检 | OpenMinis 的参数修复、required field 校验、工具专用约束和循环检测 | 神枢模型提示中规定 key=value/confirm；`parseToolCalls` 接收文本参数；危险设备操作可返回 `need_confirm` | **部分实现，强度不足** | 用 capability schema 驱动 JSON 参数验证、枚举/长度/范围/目标策略、预检报告、每次副作用的 idempotency key 与 owner confirmation |
| 持久化与迁移 | SQLite/WAL/foreign key；raw turns、parts、compact marker、dirty queue、tombstone | DO storage 保存 `soul`、cognitive snapshot、Agent run；`ExperienceMemory` 是轻量记录集合 | **基础存在，缺会话数据库语义** | 在 DO SQLite 中建立会话、消息 part、tool pair、run、attachment、compact marker、outbox/tombstone 表与显式 schema migration |
| 上下文压缩 | OpenMinis 以真实 message id 锚定摘要；确保 Responses tool pair 不被压缩拆开 | 神枢的 `gw` 候选池与 `scratchCandidates` 上限 20；无 message-id anchored compaction | **缺口** | 实现会话级 token 预算器；压缩时保持 assistant tool call 与 tool result 原子对；将摘要与锚点写入 DB |
| 浏览器运行面 | WKWebView 多 tab、cookie 备份、DOM 动作、screenshot、fetch、execute_js、cookie export | `container/task_runner.mjs:handleBrowse` 使用真实 Chromium；Web 小工作台显示截图/文本/滚动结果 | **服务端浏览器已有，移动浏览器缺统一会话模型** | 抽象 BrowserSession，按 owner/tenant/run 隔离 profile、cookie、动作序列和审计；所有 cookie 导出/脚本执行/登录动作经过独立确认策略 |
| MCP 与 OAuth | OpenMinis MCP config、CLI、OAuth PKCE、Keychain→guest 0600 bridge | 神枢当前未发现 MCP server registry、JSON-RPC transport、OAuth callback/token vault 或 worker-to-tool 安全桥 | **未实现** | 建立 MCP registry、HTTP/stdio transport boundary、OAuth PKCE、secret reference token vault、按 tool 风险分级和审计；不把 refresh token 放入普通 KV/聊天记录 |
| iOS 原生能力 | iSH native-offload 与 HealthKit/Calendar/Photos 等 handler；独立权限模型 | `ios-app/ChatViewModel.swift` 仅直连 OpenAI Chat Completions；`AppIntents` 为少量快捷指令；Worker 有 `deviceShellExec()` WebSocket relay | **移动端核心严重缺口** | 将 iOS 客户端改为神枢协议客户端；增加 owner login、Agent run UI、SSE、设备桥接、权限与结果回传；原生能力必须按 capability schema 和系统权限分层暴露 |
| iSH / PRoot Linux | iOS iSH 每命令新 fork；Android PRoot persistent shell；mount scope 与 native offload | 神枢有 Cloudflare Container、Worker DSL、设备 shell relay；没有 iSH/PRoot 子模块、rootfs、移动 guest mount 或 NOFF/NOFR 帧协议 | **未实现，不能伪称已有** | 先将 Container 定义为云端 Linux tier；另建 iOS/Linux 与 Android/Linux 兼容层的可选运行包，明确实现路径、rootfs pin、mount policy 和 ABI；不把 Container 误称为手机 iSH |
| 网络能力 | OpenMinis guest 使用宿主网络，无手机物理网卡控制 | 神枢 Container 能联网；iOS 无 Network Extension、VPN、DNS Proxy 或本机网络权限执行层 | **服务端网络可用；手机网络面未实现** | 建立“云端浏览器/Container + iOS 原生受控网络 + 局域网/主人节点”三平面；真实网卡控制不作为普通 App 承诺，Network Extension 只在获 entitlement 后启用 |
| 同步与删除一致性 | CloudKit dirty queue、LWW、30 天 tombstone、避免 full-fetch 误删 | 神枢 DO/KV 有对象存储式状态；无跨设备会话同步、outbox、tombstone 或 conflict policy | **未实现** | 用 DO SQLite outbox + version vector/LWW + tombstone，iOS 用 CloudKit 或神枢同步 API；删除/恢复均需实际多设备测试 |
| 构建供应链与 rootfs | iSH/PRoot submodule pin；rootfs 脚本需 hash 校验，OpenMinis 现有脚本自身缺 hash | Container 由 Cloudflare 建置；iOS 项目较薄；移动 Linux 无 rootfs 构建链 | **缺口** | 生成 SBOM、锁定 Container image digest、对任何 Alpine/rootfs/PRoot 输入验证 SHA256 与签名、CI 中执行 reproducibility check |
| 可观测性与测试 | OpenMinis 有 provider/tool/compaction/OAuth 测试，但 native 帧和 handler 有空白 | 神枢已有 94 项 Node 回归、Workers observability、终端实时输出；生产未完成 owner-path 全链实测 | **部分实现，实测不足** | 建立分层测试矩阵：unit、protocol frame、container integration、Worker/DO integration、iOS simulator/device、production owner-path；每项保存匿名化运行证据 |

## 2. 当前神枢真实运行链，而非模块名称

### 2.1 已接线的生产链

当前主 Worker `ShenshuCore` 已导入 `AgentStateMachineDO`，并通过 `agentLedgerRequest()`、`agentPlan()`、`agentApprove()`、`agentExecute()` 将持久化 plan、一次性确认、lease、幂等 effect 与 audit 接入 `/agent/*` 私密路由。`NexusAgentProtocol` 已提供 `PLANNED → AWAITING_APPROVAL → APPROVED → EXECUTING → SUCCEEDED/FAILED` 的受限转换、secret redaction 和稳定 hash。

`container/task_runner.mjs` 是神枢当前的真实 Linux/浏览器执行面：它提供 `/exec`、`/exec/stream`、`/read`、`/write`、`/ls`、`/def`、`/refs`、`/browse` 和 `/bridge`；浏览器由 Chromium/Playwright 支撑。神枢 Web 的“工作台”展示的 Shell 与 Web 结果必须继续来自这条链，不应再生成假终端输出。

Worker 还存在两条较弱但已运行的补充路径：`nativeSandbox()` 的 Worker DSL/模拟 shell，以及 `deviceShellExec()` 的 WebSocket 设备中继。后者发送 `{type:'shell_exec', id, code, lang, timeout:30}`，仅在 iOS/设备客户端主动注册 `shell_relay` 时可用。这不是 iSH kernel hook，也不是 Android PRoot 的 NOFF/NOFR 协议。

### 2.2 尚未真正接线或未达到产品级的模块

`NexusOrchestrator`、`NexusAPIHub`、`nexus_sse_block.mjs` 都存在于仓库，但当前检索未显示它们被 `ShenshuCore` 的生产聊天/Agent 主链导入。它们必须先接受接口与安全审计，再决定接入；不能仅因文件存在就计入“神枢已具备”。

现有 `runAgentLoop()` 使用模型输出中的文本工具标记，最多循环 5 次、每轮最多串行处理 2 个工具。它已有失败分类、重规划提示、WebSocket 事件和经验记录，但没有 OpenMinis 式规范化 provider history、稳定 tool ID、并发 source-order 回灌、成对事务提交或崩溃恢复。因此该函数是后续 Agent 内核迁移的入口，不是最终形态。

## 3. 各层落地顺序与验收

| 顺序 | 交付物 | 代码主入口 | 可证明的完成条件 |
|---:|---|---|---|
| A | `NexusTurnEngine` 统一回合内核 | `nexus_agent_core.mjs`、`nexus_do.core.mjs` | 任意 Agent run 都有 runId、roundId、typed tool call、tool result、phase、cancel reason 和 durable audit；中断后可从最后完整 tool pair 恢复 |
| B | Provider Adapter 与 SSE contract | 新建 `providers/`，替换 `buildBrainReq/parseBrainText` 的核心路径 | OpenAI Chat/Responses、Anthropic、Gemini 的 fixture SSE 都归一化为同一事件；tool IDs 在回灌前被验证；token usage/finish reason 持久化 |
| C | DO SQLite Chat/Memory store | 新建 `nexus_chat_store.mjs` 和 migration test | schema version、WAL/transaction、message parts、compact marker、outbox/tombstone 都有升级/恢复测试 |
| D | 工具安全总线 | `capabilities.mjs`、`nexus_agent_protocol.mjs`、Container bridge | 每个工具有 JSON schema、risk、confirmation binding、idempotency、timeout、output cap；unknown tool 默认拒绝 |
| E | Browser session manager | `container/task_runner.mjs`、Worker `/exec`、Web 工作台 | profile 以 owner/tenant/run 隔离；navigate/click/type/scroll/screenshot/cookie 操作可审计；登录/凭据导出必须有显式确认 |
| F | MCP/OAuth runtime | 新建 `mcp/` 与 iOS token vault bridge | OAuth PKCE、server registration、tool discovery、JSON-RPC error/timeout、secret reference 和 revocation 都有测试 |
| G | iOS 神枢协议客户端 | `ios-app/ChatViewModel.swift`、新建 Swift models/services | 不再直连裸 OpenAI Chat；能展示 SSE blocks、Agent plan/confirm/audit、工作台 stream 和设备权限结果 |
| H | 移动 Linux 可选运行层 | `ios-app/`、`android/`、`runtime/` | iSH/PRoot 不被伪造；任何引入的 submodule/rootfs 都有版本 pin、hash、mount policy 和真机/模拟器测试；若暂不可发布，UI 明确显示“云端 Container”而非“手机 Linux” |
| I | 生产验证矩阵 | `web/nexus-do/e2e/`、iOS tests、release evidence | 将匿名 Web、安全拒绝、owner Shell、Container、Browser、Agent approval、audit persistence、iOS bridge、故障恢复分别记录为真实通过或真实阻塞 |

## 4. 不能用“升级”掩盖的现实边界

普通 iPhone App 无法直接接管 Wi-Fi、蜂窝数据或获得物理网卡驱动。OpenMinis 的 iSH 使用宿主网络；神枢现有 Container 使用云端网络。真正可行的产品设计是：**Cloudflare/Container 作为云端执行平面，iOS App 作为经系统授权的原生能力平面，主人可控的局域网或长期节点作为真实网络与长期任务平面，枢语作为贯穿四者的语义/审计坐标。**

同样，Cloudflare Worker 的内置 Container 不能代替移动 iSH/PRoot；它们的生命周期、文件隔离、网络位置、权限和故障模型完全不同。后续界面、审计和模型提示必须据此诚实呈现执行位置。

## 5. 生产实测的当前发现

截至本基线编写时，生产无凭证测试已经证明主页返回新版“神枢工作台 / 内置 Shell / 内置 Web”标识，`/config`、`/sandbox/run`、`/exec`、`/agent/plan` 对匿名请求返回 `401`。但同一轮实测发现 `GET /agent/run/public-probe` 返回 `200`，这表明 Agent run 路由的 path 归一化、DO 内路由或公开/私密门之间存在需立即复核的真实行为差异。该项不能被视为通过，必须在第 7 阶段先修复或以 owner-context 解释后再发布“全面实测通过”的结论。

## 6. 后续纪律

后续每一项改动都必须在本文件对应行追加：OpenMinis 函数/协议来源、神枢文件与函数、测试入口、真实生产证据、失败或阻塞原因。未接线模块、未授权 owner-path 和未获 Apple entitlement 的能力不得写成“已实现”。

## 7. 实施进度：Phase 2 第一批（2026-08-17）

本批已新增 `nexus_turn_engine.mjs`，作为 provider-neutral 的枢语回合内核。它将 `agent_history_v1` 与 UI `stream` 明确分离；会在写入前清除 partial/in-progress assistant frame、丢弃孤立 tool result、为未配对 tool call 写入明确的 synthetic failure result，并对跨回合 `tool_call_id` 执行全局去重。`ShenshuCore.handleTalk()` 的正常完成路径现在为每次对话生成 `turnId`，在保留 UI stream 后写入 `agent_history_v1`；历史写入失败只记录诊断，不把已完成的主人对话伪装为失败。

`runAgentLoop()` 的相互独立只读/生成工具（`web_search`、`open`、`download`、`draw`、`speak`）现在通过 `NexusTurnEngine.execute()` 真实执行，最多十路并发，并按原始 `source_index` 回灌。任何 Shell、设备、写入、通知或其他副作用工具都不进入这条并发链；若模型违规混入多个副作用标记，仅首个可进入串行确认路径。

| 验证入口 | 真实结果 | 覆盖内容 |
|---|---|---|
| `node --test nexus_turn_engine.test.mjs` | 5/5 通过 | partial/孤立帧修复、ID 去重、UI/history 分离、十路上限、取消 |
| `node --test nexus_agent_loop_concurrency.test.mjs` | 1/1 通过 | 直接调用 `ShenshuCore.runAgentLoop()`；12 个输入工具仅执行 10 个、并发峰值不超过 10、源索引顺序稳定 |
| `node capsec-selftest.mjs` | 41/41 通过 | 核心写入 `agent_history_v1`、一次性确认令牌、路由前缀保护、能力门禁 |

本批还修复了一个真实的公开回退面：私密精确路径集合此前会使未知 `/agent/*` 或 `/config/*` 子路径落入公开 HTML。主 Worker 现在用 `url.pathname` 与 `PRIVATE_PREFIXES=['/agent/','/config/']` 共同判定私密命名空间，匿名请求会在前置鉴权门返回 `401`。`/config/models` 同时加入精确私密集合。该修复尚需在最终 Cloudflare 生产发布后用无凭证 HTTP 请求复测。

## 8. 实施进度：Phase 3 第一批（2026-08-17）

`nexus_provider_adapter.mjs` 现已成为 `ShenshuCore.buildBrainReq()` 与 `parseBrainText()` 的真实实现。`callBrain()` 在每个模型请求前读取并按 message-id 压缩 `agent_history_v1`，并向 Adapter 传递该规范历史；因此 OpenAI Chat、OpenAI Responses、Anthropic Messages 与 Gemini `generateContent` 都从同一份已修复 history 派生，而不是从 UI `stream` 或半截文本标记派生。

Adapter 已执行以下协议约束：`sanitizeToolId()` 将工具 id/name 收敛为 `[A-Za-z0-9_-]`；Responses 输入只产生已配对的 `function_call` 与 `function_call_output`；Anthropic 生成 `tool_use/tool_result`；Gemini 生成 `functionCall/functionResponse`；`ReasoningEcho` 按 provider 隔离 opaque reasoning；且 `finalizeToolCalls()` 在 `finish_reason` 为空时必定拒绝工具执行。`brainProvider()` 同时识别 Gemini、Anthropic 与 `/responses` 路径，并将已选方言随模型调用结果保存。

`nexus_turn_engine.mjs` 还新增 `compactAgentHistory()`：它通过 `last_compacted_message_id` 保存压缩锚点、生成受限摘要、并在裁剪点落入 tool result 时回退至对应 assistant tool request，确保不会拆开工具原子组。模型调用前自动执行至多 120 条规范消息的压缩并把结果持久化回 `agent_history_v1`。

| 验证入口 | 真实结果 | 覆盖内容 |
|---|---|---|
| `node --test nexus_provider_adapter.test.mjs` | 6/6 通过 | Chat/Responses/Anthropic/Gemini、工具 ID、SSE frame、reasoning 隔离、finish reason 门禁 |
| `node --test nexus_turn_engine.test.mjs` | 6/6 通过 | 回合修复、十路并发、取消和 message-id 锚点压缩不拆工具组 |
| `node capsec-selftest.mjs` | 41/41 通过 | Provider 接线后的核心 history 持久化与安全边界 |

## 9. 实施进度：Phase 4 第一批（2026-08-17）

`nexus_tool_preflight.mjs` 已接入 `AgentStateMachineDO.handlePlan()`、`ShenshuCore.agentPlan()` 与 `ShenshuCore.invokeCapability()` 三道真实入口。它在计划和执行两端统一校验能力与字段，处理设备动作/HealthKit 枚举、路径穿越、长度、URL scheme、通知/剪贴板等副作用提示，并保留 OpenMinis 所需的 `file_edit.new_string === ''` 删除语义。无效参数不再进入 plan、approval、lease 或 handler。

`nexus_sqlite_store.mjs` 已挂接在 `ShenshuCore` 的规范 history 写入与自动压缩路径。Cloudflare DO 具备 `storage.sql` 时会执行幂等 schema migration，启用 foreign key，投影 conversation、message、压缩 marker，并为每次 upsert/marker 创建 sync outbox；删除接口可用 tombstone 记录 retention 与 revision。无 SQLite runtime 的本地测试会明确报告未启用，绝不伪称同步成功。Cloudflare 平台管理 SQLite 的 WAL/log，因此应用不会执行不受支持的 journal pragma。

| 验证入口 | 真实结果 | 覆盖内容 |
|---|---|---|
| `node --test nexus_tool_preflight.test.mjs` | 4/4 通过 | unknown/字段拒绝、设备枚举、路径防护、空字符串删除、确认 warning |
| `node --test nexus_agent_core_preflight.test.mjs` | 1/1 通过 | Agent DO 在 `createPlan()` 前阻断无效 exec/device 参数，并写入归一化有效参数 |
| `node --test nexus_sqlite_store.test.mjs` | 4/4 通过 | 幂等 migration、脱敏 history、outbox、tombstone、无 SQLite 诚实降级 |
| `node capsec-selftest.mjs` | 41/41 通过 | 核心 history、安全路由、审批与能力门禁未回归 |

## 10. 实施进度：Phase 5 第一批（2026-08-17）

内置 Web 工作台的真实 Container 运行器 `container/task_runner.mjs` 现使用 Playwright Chromium。浏览任务使用单槽队列，所有 URL 必须为 HTTP(S)，动作最多 25 个，单次导航/脚本预算被 Worker 与 Container 双侧收敛至 **45 秒**；页面点击后额外等待 `domcontentloaded`，并对 `document.body` 为空的导航竞态安全降级。测试曾真实发现点击 `example.com` 后跨域导航导致 `document.body.innerText` 访问空对象；已修复并通过重试验证。

本地端到端测试不是静态分析：启动 runner 后，真实 Chromium 访问 `https://example.com` 成功返回标题、正文；点击链接成功到达 `https://www.iana.org/help/example-domains`，返回正文与 79,500 字节 JPEG base64 截图。并发两个含 2 秒等待动作的浏览任务总耗时为 **11,122 ms** 且均返回 `ok:true`，与单槽串行模型一致，未让两个操作并行争抢 Chromium。

iOS 方面新增 `NexusKeychain.swift`、`NexusClient.swift` 与 `NexusDeviceBridge.swift`。聊天不再直连第三方 `/chat/completions` 或从 `@AppStorage` 读 API key，而是用 Keychain owner token 请求 Cloudflare 神枢 `/talk`、`/agent/plan`、`/agent/approve`、`/agent/execute` 与 `/wsticket`。WebSocket 只在 HTTPS 换取 30 秒一次性 ticket 后建立，owner token 不进入 URL。`NexusDeviceBridge` 与 Worker 的 `device_shell_register`、`shell_line`、`shell_result` 帧兼容；若未接入经审计本机运行时，明确返回 unavailable，**不会伪称 iOS 拥有 iSH/PRoot、root 或物理网卡控制能力**。

工程配置新增主应用 App Group entitlement、`NSLocalNetworkUsageDescription`、`_nexus-bridge._tcp` Bonjour 声明和 Packet Tunnel extension target/entitlement。`PacketTunnelProvider` 仅在 Apple 签名授权且存在显式受管理 gateway 时设置 tunnel 网络参数；缺少 gateway 时明确拒绝启动、不修改系统网络。当前 Linux CI 环境没有 Swift/Xcode toolchain，因而尚不能作真机编译/Network Extension entitlement 签名验证；此项将保留至最终人工 Xcode 验收，而不把源码生成误报为 iOS 真机已启用。

| 验证入口 | 真实结果 | 覆盖内容 |
|---|---|---|
| 本地 `task_runner.mjs` + `curl /browse` | 通过 | Chromium 导航、正文、截图、点击跨域导航 |
| 两并发 `/browse` 请求 | 11,122 ms、两者 `ok:true` | Chromium 单槽队列实际串行化 |
| `node --check container/task_runner.mjs` | 通过 | 浏览运行器修复后的 Node 语法 |
| `swift --version` | 不可用 | 如实记录当前环境无法替代 Xcode 真机构建 |

## 11. 实施进度：Phase 6 第一批（2026-08-17）

Web 工作台新增可见的 **Agent 控制台**入口（能力区与设置区均可访问）。主人可以输入受预检的 JSON 参数，通过真实 `/agent/plan` 创建带 `idempotencyKey` 的计划；对高风险 plan，页面仅在内存保留服务端返回的一次性 token，必须显式“载入本次令牌”并点击确认，才显示执行按钮。执行与刷新审计分别调用 `/agent/execute`、`/agent/audit`；页面所有 run、错误、结果和审计均使用 `textContent` 呈现，避免将返回内容作为 HTML 注入。

原有终端和内置 Web 工作台仍保留。前端已通过 `node build.mjs` 打包，`index.built.html` 包含 `sheetAgent`、`agentCreatePlan`、`agentApprovePlan`、`agentExecutePlan` 与 `openAgentConsole`，不是孤立 API 方法。

原生 iOS 控制面也移除了模拟监控：`MonitorView` 不再产生随机 CPU/内存/服务状态，而是使用 `NexusClient.stats()` 读取 Worker `/stats` 的运行时间、存储估算、经验、能力、世界图与内在记录，并真实呈现未配置令牌和网络失败。个人页入口已改为“神枢连接”；`ChatViewModel`、`APIConfigView`、`AppIntents` 都仅从 `NexusKeychain` 读写 owner token，Swift 全仓检索未再发现 `owner_token`、`@AppStorage("api_key")`、`/chat/completions`、`Double.random` 或占位服务器地址。

| 验证入口 | 真实结果 | 覆盖内容 |
|---|---|---|
| `node build.mjs && node --check nexus_do.mjs` | 通过 | Web Agent 控制台已进入 Worker 打包 HTML，主模块可解析 |
| 全套 Node 回归 | `41` 核心安全断言 + `28` 协议/存储/预检断言通过 | UI 接线未破坏 Worker、Agent、安全与持久化主链 |
| iOS Swift 仓库检索 | 无旧密钥/裸 API/随机监控命中 | Keychain + Worker 协议迁移覆盖聊天、设置、Siri 和监控 |
| Xcode/Swift 编译 | 当前 Linux 环境不可用 | 已同步主 Xcode Sources/entitlement；Packet Tunnel 真机签名与 Extension target 仍需 macOS/Xcode + Apple entitlement 验收 |

> 同步协议当前已具备持久化 outbox、revision 与 tombstone 数据面；将其暴露给 iOS/跨设备客户端的鉴权 API 与冲突策略 UI 仍须在后续 iOS/Web 控制面阶段完成。未把“数据面已建立”误写为“多设备同步已上线”。
