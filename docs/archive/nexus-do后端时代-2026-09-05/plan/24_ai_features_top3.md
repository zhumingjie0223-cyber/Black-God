# 24 AI产品·核心功能提取

> 覆盖 24 个产品，功能数量按实际价值灵活

---

## Cursor
**功能1**：Tab 补全 - 双向 prefix/suffix infilling 补光标中间，而非单向 next-token；上下文按"最近编辑文件、已接受补全、当前诊断报错、光标轨迹"加权，"最近改了什么"优先于"全仓库相似代码"。多级模型分流（本地小模型出快速候选、远端大模型出强候选、reranker 决定展示），配合 speculative 预测与候选缓存把体感延迟压到 100-300ms。

**功能2**：Diff 级输出 - 输出的不是"一段代码"而是"当前位置的最小编辑"，可直接 accept，把补全从参考建议变成确定性操作。

**功能3**：Shadow Workspace - 真实工作区的 overlay 影子快照。AI 在影子层做多文件修改、重建索引、跑类型检查与测试，全程不污染真实文件；验证通过才 writeOverlaysToDisk，失败直接 discard，是 Composer 敢做大规模改动的地基。

**功能4**：Patch Agent Loop - 固定协议 search/read → plan → applyPatch → 打到 shadow → getDiagnostics/runCommand → repair → final diff。工具集收敛为 6 个原语，模型强制输出结构化 JSON（thought + actions），杜绝一次性整体生成。

**功能5**：全链路可回放 - 所有编辑必须可 diff、可撤销、可重放，错误恢复靠工程约束而非模型自觉。

---

## v0 by Vercel
**功能1**：增量补丁生成 - 每轮不重新生成整个项目，模型输出被强约束为结构化文件操作（增删改文件、装依赖、执行命令），经 parser → validated file operations → workspace state 三层落盘，绝不把模型原始文本直接当文件写入。

**功能2**：真实运行的 Preview 闭环 - Preview 是真跑起来的 dev server 渲染结果，非模型想象截图。TypeScript/ESLint 错误、构建错误、runtime exception、页面截图与 DOM 状态全部回传给模型做下一轮修复，形成自动纠错环。

**功能3**：v0-MDX 流式 Artifact 协议 - Markdown + JSX + 元数据混合格式（`<Artifact><File path="...">`）。核心是数据模型：一条流式消息同时承载解释文本、多文件、路径映射，前端可边流边增量解析渲染，高亮与折叠都挂在这层。

**功能4**：microVM 级 Preview 沙箱 - 弃用浏览器内 WebContainer（撑不住 Next.js SSR、npm 依赖、多用户隔离）。每会话起独立工作区 → 容器或 Firecracker 类 microVM → dev server → 反向代理 URL → iframe 加载，附带超时、限额、进程回收与截图自动化。

**功能5**：生态垂直收窄 - 死磕 Next.js + React + Tailwind + shadcn/ui + AI SDK 一条栈，换来更高生成成功率和一键部署 Vercel 的直通链路。

---

## Devin
**功能1**：会话级独立工作区 - 每个任务分配容器化环境，具备完整 shell、文件系统和网络，支持 `POST /projects/:id/files`、`/run` 等原子操作，任务间完全隔离、可并行、可回收。

**功能2**：长时程自主执行 - 靠"执行—观察报错—修复"持续循环推进，进程可跨小时存活，中间状态持久化，不追求单轮正确。

**功能3**：可编辑计划层 - 接任务后先生成显式分步 Plan（节点带 pending/in-progress/done/blocked 状态），引擎按节点推进并回写结果；用户可运行中直接改 Plan，Devin diff 新旧 Plan 后从被改节点重新调度，避免长任务在错误方向跑完整条路。

**功能4**：沙箱浏览器操作 - 独立 Chromium 内完整操作网页（登录/填表/搜索/抓取），视觉层走 screenshot→坐标→点击，DOM 层走 CDP 直接操作，两路互补，结果回传作下一步决策输入。

**功能5**：知识即时获取 - 任务中主动 web 搜索、读文档、看 StackOverflow，结果经摘要注入上下文，而非依赖训练知识，可处理最新 API、版本变更与项目特定规范。

**功能6**：工程工作流集成 - 作为 Slack bot 接任务、更新进度、等待审批，与 Jira ticket 双向同步，把 AI 任务嵌入已有流程而不要求切换工具。

---

## ChatGPT Operator / Computer Use
**功能1**：视觉 Agent 闭环 - 不生成一次性脚本，每步重新观察：截图 → 模型判断页面状态与任务进度 → 输出 action → 执行 → 重新截图验证。每个动作前重新截图并基于当前帧重定位（不缓存坐标批量点击），点击后对比动作前后截图（焦点/URL/DOM 抖动、loading spinner 消失）判断是否真正生效，未生效则重试或换目标——开环变闭环，对抗前端非确定性的核心。

**功能2**：视觉 grounding 到坐标 - 把"点击登录按钮"直接映射为 `{"type":"click","x":640,"y":420}`，绕开 DOM 选择器脆弱性，对 canvas、远程桌面、非标准页面同样有效。

**功能3**：混合执行层 + 统一动作抽象 - 决策层只看像素保证泛化，执行层底下可为 CDP/Playwright/原生鼠标键盘注入，对模型统一暴露 `click/type/scroll/keypress/drag`；模型不感知具体执行技术，DOM 自动化与纯像素两模式可切换。

**功能4**：观察-思考-行动推理轨迹 - 每步先生成 reasoning（当前页面状态、任务进度、下一步及理由）再输出结构化 action。CoT 既提升复杂页面定位准确率，也构成可审计日志，出错时能区分是"看错页面"还是"决策错误"。

**功能5**：截图 Token 化与成本权衡 - 每步截图编码成 vision token 开销大且拖慢延迟，系统做动态降采样与关键区域裁剪（viewport 归一化到固定坐标系，模型输出坐标再反投影回真实像素），在可点击元素清晰度与单步 token 预算间平衡，坐标标准化也让输出在不同尺寸/DPI 下可迁移。

**功能6**：长任务状态机 + 跨页记忆 - 维护当前目标、子任务树、已完成步骤，支持等待/重试/回退/重规划。跨多页面多标签抽取并结构化持久化关键信息（已填字段、购物车、目标参数），避免只依赖单帧而"失忆"，也支撑回退时恢复正确中间状态；全程跑在独立 cookies/网络/文件的隔离远程容器里。

**功能7**：高风险动作接管协议 - 登录、支付、发消息、删数据等强制用户确认；遇验证码、2FA、敏感凭据不尝试破解，暂停任务把控制权与实时画面交还用户，用户在同一远程会话手动完成后 Agent 无缝续跑状态机——将能力边界与安全边界显式建模为 handoff 节点。

**功能8**：拟人化反检测 - 应对 bot detection（鼠标轨迹分析、点击时序、navigator.webdriver、指纹），通过真实浏览器 + 拟人化鼠标轨迹/输入节奏、逐字符 type 而非瞬时填充、合理动作间隔降低被 challenge/封禁概率，同时保留隔离容器的干净指纹。

---

## Perplexity
**功能1**：Query Planner 搜索编排 - 先判断是否需要联网、拆解子问题、生成多组并行 Query、决定搜索深度和预算再执行，核心资产是搜索策略而非模型本身。

**功能2**：多跳证据图 - 从 `Query→Top-K→LLM` 升级为 `Decompose→Retrieve→Plan→Generate`。并行搜索结果经 Evidence Processor 做去重、相关性排序、片段切分、时间/权威性判断、交叉验证，构建证据图再综合。

**功能3**：断言-证据-来源三元对齐 - 维护 `Claim↔Evidence Span↔Source URL` 映射。回答先拆成原子断言，每个断言反查证据判断支持/部分支持/冲突再插 citation，无法支持的内容降低语气或删除。

**功能4**：Entailment 引用校验 - 解决 citation correctness 而非 presence，对「句子 A [1]」做蕴含检测，确保来源真的支持整个断言而非半句话。

**功能5**：多因子置信度打分 - `Confidence = Evidence Entailment × Source Quality × Cross-source Agreement × Freshness × Retrieval Reliability`。每来源带 rank/authority/freshness_score 与 published_at/retrieved_at，官方文档权重高、搜索摘要权重低、旧文答实时问题降权。

---

## Cline
**功能1**：Extension Host 侧 Agent 状态机 - agent loop 跑在本地 Node.js 侧而非 Webview 或模型端，天生持有文件系统、Terminal、VS Code API 的真实副作用能力；消息历史、token 预算、abort 与工具执行状态全部由 task controller 持有并可持久化，Webview 仅通过 postMessage/RPC 传输入、审批、取消信号。

**功能2**：流式工具块解析 + 先审后执 - 模型响应边流式渲染边累积解析 tool_use/XML 工具块，仅当工具块完整才进入权限判定与执行，用户看到「将要执行什么」再放行。

**功能3**：Plan/Act 双模式切换 - 规划与执行拆成两个运行模式，各绑不同 system prompt 与工具白名单。Plan 模式仅能读文件、搜索、提问、产出方案，屏蔽写文件/跑命令等破坏性工具，用于信息不足时先对齐意图；确认后切 Act 解锁全套工具。两模式可分别配不同模型（Plan 用推理强的贵模型、Act 用便宜快的），切换时共享同一份任务上下文，从架构上避免「没想清楚就动手」。

**功能4**：Checkpoint 影子仓库回滚 - 每次文件写入前后在独立 shadow git 仓库对工作区打快照，不污染用户 `.git`，每个 checkpoint 对应一次 agent 动作。用户可在任意历史消息节点「恢复到此处」，diff 快照与当前状态并还原文件，实现对一连串多文件、跨命令修改的原子回滚，覆盖 VS Code undo 栈无法处理的场景。

**功能5**：MCP 动态工具接入 - 作为 MCP Host 连接任意 MCP Server（本地 stdio 或远程 SSE/HTTP），启动时通过 `list_tools`/`list_resources` 拉取 schema 动态拼进 system prompt 工具清单，让模型像调内置工具一样调用数据库、浏览器、API。甚至能让模型自己编写并注册新 MCP server，工具集运行时增量扩展而非编译期写死。

**功能6**：风险分级权限矩阵 - 权限非「全放/全手动」二元开关，而是按工具类别（读文件、写文件、执行命令、浏览器、MCP、外部请求）分别配置自动批准，叠加「本会话最大自动执行次数」上限；命令执行还维护允许/拒绝前缀白名单，命中安全前缀自动跑、其余人工审批。

**功能7**：终端进程管控与输出流式回收 - 通过 VS Code Terminal Shell Integration API 拿到命令执行边界（开始/结束/退出码）而非盲塞字符串等结果，流式读取运行进程输出增量喂给模型，识别长驻进程（如 dev server）不阻塞后续，输出经截断/窗口化回填，退出码用于判断成败。

**功能8**：上下文按需窗口化与 @ 提及注入 - 超长文件不整塞上下文，支持按行区间读取、结合搜索只取相关片段形成「文件内容窗口」；用户可用 `@file`/`@folder`/`@url`/`@problems` 把文件、目录树、网页、诊断报错精确注入当轮 prompt，框架负责解析引用、抓取内容并做体积控制。

---

## CrewAI
**功能1**：Crew 与 Flow 双引擎 - 把「自主协作」与「确定性编排」拆成两套运行模型。Crew 是 Agent 自组织高自主模式（Process.sequential/hierarchical，manager 动态分配）；Flow 是事件驱动状态机，用 `@start`/`@listen`/`@router` 把方法节点连成有向图，通过 `self.state`（Pydantic 或字典）显式传递结构化状态。需要创造性丢 Crew、需要分支/循环/条件用 Flow，且 Flow 节点内可嵌套 kickoff 整个 Crew，实现「宏观确定性 + 微观自主性」。

**功能2**：Hierarchical 动态委派 - 层级模式下自动注入 manager Agent（可自定义 manager_llm/manager_agent），它不执行任务，而是拆解目标、按 worker 的 role/goal/backstory 语义匹配分配子任务，用 `AgentTools`（Delegate work/Ask question）让 Agent 互相调用，并收集输出做质量评估与重试，把静态编排升级成运行时 LLM 推理的动态调度。

**功能3**：结构化输出与上下文管道 - 每个 Task 支持 `output_json`/`output_pydantic` 强约束 schema，框架把自由文本解析校验成类型安全对象；`context=[task_a, task_b]` 显式声明依赖，让前置输出精准注入当前任务而非拼接全部历史，配合 `output_file` 落盘与 `callback` 钩子形成「schema 约束→依赖注入→持久化」管道，避免上下文膨胀与格式漂移。

**功能4**：四层可插拔记忆系统 - 开启 `memory=True` 自动挂载多级记忆：短期用向量库（默认 ChromaDB + 嵌入）做 RAG 语义检索，长期用 SQLite 持久化跨会话经验，实体记忆追踪人物/组织/概念关系，上下文记忆维持任务链连贯。检索在每个 task 前自动触发并注入 prompt，嵌入模型与存储后端均可替换。

**功能5**：强类型工具封装 - 通过 `BaseTool` 子类或 `@tool` 装饰器定义工具，用 Pydantic `args_schema` 声明参数类型并生成 function-calling schema 校验入参；内置 crewai-tools 提供 Serper 搜索、网页抓取、RAG 检索、代码执行等，工具可挂 Agent 级或 Task 级，配合 `cache_function` 缓存、`max_usage_count` 限流控制成本。

**功能6**：无 LangChain 轻量内核与生产化 - 底层重写执行引擎不依赖 LangChain，直接基于 LiteLLM 统一对接上百种模型（OpenAI/Anthropic/Ollama），减少抽象层开销；生产侧提供 `kickoff_async`/`kickoff_for_each` 批量并发、Flow 的 `@persist` 断点续跑、`crew.train` 人工反馈迭代、AgentOps/Langtrace 可观测性集成。

---

## LangGraph
**功能1**：可恢复的有状态控制流 - State/Node/Edge/Checkpoint 四件套把 Agent 从「步骤顺序」升级成状态机，长流程崩溃后可从 checkpoint 恢复重放；显式条件边支持工具调用、失败重试、反思循环、并行分支，控制流由图结构而非 Prompt 决定，可审计可调试。

**功能2**：Interrupt 人机协同节点 - 流程可在任意节点暂停等待人工审批或外部事件，恢复时状态完整，是审批流、运维自动化落生产的前提。

**功能3**：Time Travel 状态回溯与分支 - Checkpoint 是 append-only 历史链，每个带 parent_config 形成树状拓扑。可用 `get_state_history` 遍历任意历史节点，从中间 checkpoint fork 新分支重放（update_state 注入修改后状态再执行），实现「回到第 3 步改参数重跑而不影响原线」，本质是给执行加了 Git 式版本树。

**功能4**：Channel + Reducer 状态合并 - State 每个字段建模成 Channel，通过 reducer（如 `add_messages`、`operator.add`）定义并发写入如何合并。多并行节点同写一字段时，Pregel 风格 BSP 执行模型在每个 super-step 结束后统一 apply reducer 避免竞态，让 fan-out/fan-in 分支确定性聚合而非最后写入者胜出。

**功能5**：Send API 动态扇出 - 边在编译期静态确定的限制被打破，Send API 允许节点运行时按数据动态生成 N 个下游任务实例（`return [Send("worker", {"item": x}) for x in items]`），各带独立局部 state 并发执行，是运行时决定并行度的 map-reduce 原语，适合「切成不定数量 chunk 分别处理再汇总」。

**功能6**：分层子图与命名空间隔离 - 子图可作为 node 嵌入父图（`add_node("sub", subgraph)`），父子图各维护独立 state schema，通过共享 key 或输入/输出映射通信。Checkpoint namespace 让父子图状态按层级路径隔离存储，既能整体恢复也能单独调试子图，支撑大型多 Agent 系统模块化组合。

**功能7**：持久化后端可插拔 + 跨会话记忆 - Checkpointer 抽象成统一接口（BaseCheckpointSaver），MemorySaver/SqliteSaver/PostgresSaver 一键切换，state 用可配置 serde 序列化；此外 Store 层提供跨 thread 长期记忆（namespace+key 组织，支持语义检索），区别于单会话 checkpoint 短期状态，让 Agent 记住用户历史偏好。

**功能8**：流式多粒度输出 - 通过 `stream_mode` 支持 `values`（每步完整状态）、`updates`（增量 diff）、`messages`（token 级流式）、`debug`（含 checkpoint 元数据）多种订阅粒度，底层基于事件总线在每个 super-step 推送，前端既能拿打字机 token 流又能实时观测节点级状态变迁，无需等图跑完。

---

## Gemini Deep Research
**功能1**：可修改的研究 DAG - Planner 输出可并行分支的研究 DAG（而非线性链），用户可在执行前确认或修改计划
**功能2**：信念状态闭环 - Plan→Act→Observe→Update→Replan 循环，每轮显式维护「已知事实/证据/冲突/未答问题」四元状态，用 information gain 决定深挖、交叉验证还是停止
**功能3**：五层上下文分层 - 原始层/抽取层(evidence card)/工作记忆层(计划+冲突表)/合成层/审计层，1M token 用于减少摘要层层传递的信息损失而非硬塞
**功能4**：跨文档审计回看 - 成文后用超长上下文重载原文，校验每个结论是否被引用片段真实支撑，同时发现跨文档矛盾、重复引用与时间线冲突
**功能5**：双停止条件 - token/时间/搜索轮次的预算约束与关键问题覆盖率、边际新增信息共同决定收工时机

---

## OpenDevin / OpenHands
**功能1**：CodeAct 可组合动作 - Agent 动作是可写可组合的代码而非固定工具枚举，动作空间表达力直接决定复杂任务的天花板
**功能2**：一任务一容器隔离 - 每个 SWE-bench issue 对应独立 container + workspace + git 状态，杜绝 patch 串污染、依赖互扰与结果不可复现
**功能3**：分阶段网络策略 - 装依赖阶段受限出网、测试阶段断网，把「pip 下载失败」与「代码写错」两类失败分开，避免评测噪声
**功能4**：全链路版本固定 - 镜像 digest、依赖版本、base commit、测试命令全部锁死，patch 与环境绑定并保留完整日志，保证可复现可对比
**功能5**：轨迹级可观测 - 工具调用、代码、中间轨迹全透明，prompt/工具/模型/评测均可替换，是其作为研究平台而非黑盒的核心价值

---

## Grok DeepSearch
**功能1**：模型驱动迭代检索 - 由 `while not enough_evidence and budget_left` 循环驱动，每轮由模型根据证据覆盖率与冲突程度决定下一步查询目标
**功能2**：X 平台实时索引 - 新帖流式进入倒排+向量混合索引，配合时间衰减排序、趋势聚类、机器人/敏感内容分层过滤，核心资产是实时索引+低延迟检索而非临时抓取
**功能3**：平台内生排序信号 - 帖子互动量、转发关系、账号质量网络作为排序特征，是接外部搜索 API 拿不到的独有信号
**功能4**：多检索器路由 - 网页/X/新闻/数据库/上传材料走不同检索器，Evidence Store 统一存 URL/发布时间/作者/原文片段/实体关系/可信度
**功能5**：长 CoT 内部规划器 - 长思维链仅用于拆解、识别证据缺口、处理来源冲突、规划工具顺序，对外只暴露 Plan/Evidence/Answer 三层，并用最大步数、单步超时、低价值循环检测防空转

---

## Amazon Q
**功能1**：AWS 实时诊断闭环 - 将 CloudFormation Stack events、CloudTrail 失败调用、CloudWatch Logs Insights 查询工具化，把逻辑资源映射到实际资源后关联日志与权限错误，形成「证据检索→故障假设→修复建议」闭环，诊断基于实时 API 返回的真实状态而非模型记忆
**功能2**：IAM 边界内 Agent 执行 - Agent 身份受 IAM Identity Center、SCP、permission boundary、session policy 多层约束，读诊断与写操作拆成不同工具与权限域，LLM 本身拿不到无限 AWS 权限
**功能3**：ACL 前置过滤检索 - Confluence/Jira/S3 的访问限制被镜像成可过滤 principal 列表并进入检索条件本身，而非先召回再靠 LLM「自觉不泄露」
**功能4**：增量同步与删除传播 - 连接器保存 source version、cursor、content hash，正确处理文档修改、删除及权限变更导致的可见性变化，避免索引残留「幽灵文档」
**功能5**：开源引用追踪 - 补全结果与训练语料中开源片段做匹配，输出时标注来源与许可证，规避企业代码合规风险
**功能6**：版本迁移 Agent - Java/.NET 跨文件级代码转换，配合 workspace 索引做依赖改写与 API 替换，而非逐文件翻译

---

## Apple Intelligence
**功能1**：选区级局部 AI 操作 - 交互单元不是聊天窗口而是"选中一段→改写/总结/翻译/转表格→生成 diff→accept 或 reject"，AI 输出以补丁形式落到结构化文档中，用户保有逐条否决权。比全文重写的生产力闭环短得多。
**功能2**：短期上下文与长期记忆分离 - 临时任务上下文任务结束即过期，长期记忆需用户明确授权才写入，审计日志脱敏后按合规期限单独保留，三类数据独立 TTL 和独立开关。
**功能3**：可审计的决策证据链 - 保留"输入→采用了哪些上下文→调用了哪些工具→用了什么权限→谁批准了高风险动作→输出"的完整轨迹，不暴露思维链但保留证据，满足 GDPR 可解释要求。
**功能4**：端侧优先 + 私有云计算的分层推理路由 - 请求先由端侧小模型（约 3B，量化后驻留内存）尝试处理；当任务复杂度超过端侧能力阈值时，路由器将请求升级到 Private Cloud Compute。关键设计：PCC 节点运行在定制 Apple Silicon 服务器上，操作系统镜像可被公开审计（build 哈希发布供研究者验证），节点不保留任何请求数据（无持久化存储、请求处理完即销毁内存），且客户端通过远程证明（remote attestation）验证服务端跑的正是已公开审计的镜像后才发送数据——用密码学保证"云端不可信也无法读取用户数据"，而非靠隐私政策承诺。
**功能5**：语义索引层驱动的 App Intents 编排 - 系统在端侧维护一个跨 App 的语义索引（照片、邮件、日历、消息等结构化实体 + 向量化语义），当模型需要执行动作时，通过 App Intents 框架把开发者声明的操作暴露为可调用工具（类似 function calling，但 schema 由 App 静态注册在系统中）。数据流：用户意图 → 语义检索相关实体 → 规划器匹配可用 App Intents → 参数填充 → 执行。设计决策是让第三方 App 无需集成大模型，只声明能力，编排与推理由系统统一承担，避免每个 App 各自造轮子和重复索取权限。
**功能6**：可控生成的结构化输出（Guided Generation） - 面向开发者的 Foundation Models 框架用 Swift 宏（`@Generable`/`@Guide`）把 Swift 类型直接映射为模型输出约束，推理时通过受约束解码（constrained decoding）在 token 采样阶段强制输出符合 schema，而不是先自由生成再解析纠错。这保证模型永远吐出可直接反序列化的强类型对象（枚举只能落在合法值域、字段类型不出错），把"LLM 输出不可靠"从运行时异常降级为编译期契约。
**功能7**：LoRA Adapter 热插拔的单基座多任务架构 - 端侧只驻留一个共享基础模型，各具体能力（摘要、改写、邮件回复、Genmoji 等）通过任务专属的低秩适配器（LoRA adapters）实现，运行时按当前任务动态加载对应 adapter 而非切换整个模型。收益：多任务复用同一份基座权重，显著降低内存与存储占用；Apple 可独立训练、评估、按需下发/更新单个 adapter，无需重新分发几 GB 的完整模型。
**功能8**：差分隐私 + 合成数据的模型改进闭环 - 为在不采集用户真实内容的前提下改进模型，Apple 用差分隐私聚合信号：在端侧对合成数据变体做匹配，只回传经加噪的、无法反推个体的统计信号（哪些合成样本更贴近真实使用分布），服务端据此校准合成训练语料。设计核心是"从不上传原始邮件/消息文本"，用 DP 噪声保证单个用户对聚合结果的贡献不可识别，实现群体级质量提升与个体级隐私的解耦。

---

## Mistral Le Chat Agent

**功能1**：Agent + Conversation 双状态模型 - 把「可复用运行时配置」（instructions/model/tools/completion args/handoff targets）和「执行状态」（消息流、tool 结果、转交记录）彻底分离。Agent 是长期对象而非一次性请求参数，同一配置可跨多个 Conversation 复用，比单次 Chat Completion 更接近轻量工作流运行时。

**功能2**：Handoff 作为一等公民 - agent-to-agent 转交是内置的受控 tool call，不是应用层拼装。本质是**路由权转移**而非多模型并发：Agent A 生成 handoff → B 接管后续推理 → 共享/复制必要上下文 → 结果回流用户。生产侧可挂白名单、最大转交深度、循环检测、上下文裁剪、最终负责 Agent 标记。对比 OpenAI Assistants 需要在应用层自己编排多 Agent，这是 API 表面级的降复杂度。

**功能3**：对话原生的长会话执行 - 不走 Run 生命周期（`requires_action` 等待外部提交那套），执行体验更接近 Chat Completion 流式。代价是任务执行的显式生命周期控制弱于 Run 驱动模型，强项是长期 Agent + 持续对话场景。

**功能4**：三层 Tool 统一接口 - 内置工具（联网搜索、代码解释器、文档/文件检索）、自定义 function tool（业务方给 JSON Schema，模型只产参数）、handoff，三类走同一套调用协议。文件与检索直接绑定到 Agent/Conversation，省掉 Thread + Vector Store + Run 的三段式组合。
**功能5**：追加式对话 + 服务端状态持久化 - Conversation 是服务端持有的可追加实体，客户端不回传全量 history，只通过 conversation_id + append 语义挂新一轮输入；每次 append 返回带 entry_id 的结构化 entries（message/tool_execution/handoff/agent_answer），而非扁平列表，支持工具链可审计回溯
**功能6**：Le Chat Canvas 协作编辑 - 文档和代码在 canvas 中可结构化编辑；AI 修改以增量 patch 而非全量替换方式应用，多版本历史可回溯，与 agent 对话同步进行不打断上下文
**功能7**：欧洲合规优先架构（GDPR-native）- 数据主权从 API 设计层介入，对话数据可选存储在 EU 境内节点，工具调用参数支持字段级脱敏，对企业客户提供数据不出境承诺；这是与 OpenAI/Anthropic 对企业客户的核心差异化

---

## Devin API

**功能1**：Session-centric 异步任务模型 - `POST /v1/sessions` 只返回 `session_id` 立即出栈，不阻塞等待完成。所有消息、工具调用、产物、错误全部挂在 Session 下。这是把 API 从「prompt 转发器」重构成 **Job + Runtime + Event Log**——普通 LLM 是 request→response，这里是排队→启沙箱→读仓库→规划→多轮工具循环→编译测试→等用户→继续→产出 patch/PR。

**功能2**：可阻塞的状态机 - `new/queued/running/waiting_for_user/blocked/completed/failed/cancelled`。关键在 `waiting_for_user` 和 `blocked`：普通 LLM 的失败只有请求失败，Agent 会暂停等授权、等决策后再恢复。状态接口必须回 `updated_at` + 当前阶段 + 阻塞原因 + 产物链接，否则客户端无法判断该等还是该介入。

**功能3**：三层 Snapshot 恢复基线 - 不是存聊天记录。**Workspace**（仓库工作区、未提交修改、已装依赖、生成文件、工具链状态）+ **Runtime**（VM/容器磁盘、系统包、浏览器与服务进程环境、环境变量引用）+ **Agent State**（已完成阶段、关键发现、待办、工具输出摘要、用户约束）。核心洞见是**不能拿模型上下文当唯一恢复源**——上下文会被压缩、工具输出会过期，恢复必须靠持久化事件 + 结构化任务状态。

**功能4**：Session 创建即冻结运行环境 - `repo/branch/snapshot_id` 在创建时固定仓库、分支、权限、资源规格，保证整个长任务期间环境不漂移，也让 snapshot 恢复有确定基线。

**功能5**：长任务的事件流 + 幂等 - `GET /v1/sessions/{id}/events` 配 webhook 替代高频轮询；消息接口带幂等键，防止客户端重试在长任务中触发重复执行（这是同步 API 不存在的问题）。

---

## Bolt Enterprise

**功能1**：WebContainer 浏览器内运行时 - 整个 Node 执行环境、文件系统、依赖安装跑在浏览器里，无需后端容器即可启动项目。这是 Bolt 区别于所有服务端沙箱方案的根本技术底座。

**功能2**：Data Plane / Control Plane 架构切分 - Enterprise 不是「开源版加几个权限页」。Data Plane 管编辑器、Agent、沙箱、文件依赖、实时协作；Control Plane 管租户/组织/项目/成员、SSO+SCIM、策略权限、配额计费、模型治理、审计风控、数据保留。两层解耦才能支撑多租户合规。

**功能3**：Codeflow 混合协作模型 - 不用纯 Git merge（不够实时）也不用纯 CRDT（大文件和二进制成本爆炸）。分层处理：短文本编辑走 OT/CRDT（服务端维护项目递增版本号，客户端 base_version 落后时做转换或按字符/块 ID 合并）；文件增删改名走路径级操作；大文件/二进制走锁或最后写入优先并显式冲突；Git 分支合并仍交回三方 merge，不让实时协议越界。

**功能4**：Agent 操作携带 base version - 最容易出事故的点是 Agent 和真人同时改同一文件。解法是给每个 Agent 写操作绑定基础版本号，让 Agent 的批量修改进入和人类编辑同一条冲突解决路径，而不是直接覆盖工作区。

**功能5**：租户隔离沙箱池 - 从「单个 WebContainer/Docker」升级为按租户隔离的沙箱池 + 资源配额 + 自动回收 + 审计，配合项目持久化、版本快照、备份恢复替代浏览器内存/IndexedDB。

**功能6**：私有 registry 代理层 - 依赖安装从直连公网 npm 改为私有 registry + 代理缓存 + 凭据注入 + 包白名单，这是企业环境下供应链安全的硬需求，也顺带解决安装速度。

**功能7**：模型治理网关 - Agent 层不再是直连自配 LLM API，而是走模型路由 + 配额 + 成本统计 + 策略拦截 + 企业自有模型接入，把 LLM 调用变成可审计可管控的受控资源。## GitHub Copilot
**功能1**：任务编译器 - 将一句自然语言编译成可执行任务图（目标→子问题→数据源→Agent分工→输出页面结构→验证规则），以 JSON 任务描述替代聊天框，把"AI 对话"升级为"AI 交付"

**功能2**：证据绑定组件 - 构建 Evidence Graph（Source→Evidence→Claim→Page Component），每个结论、数字、卡片各自绑定来源 URL、原文片段、抓取时间与可信度，支持点击溯源与局部审计更新

**功能3**：页面组件 DSL + 增量刷新 - 定义有限组件集（Summary/ComparisonTable/Timeline/Ranking/Map/Gallery/FAQ/SourceList/Recommendation），模型只输出 DSL/JSON 由渲染器稳定呈现；变更时只重跑受影响模块，降低成本、延迟与页面漂移
**功能5**：Fill-in-the-Middle（FIM）补全推理 - 补全模型不是纯左到右生成，而是用 FIM 训练目标。将代码切成 prefix/middle/suffix 三段，重排为 `<PRE>prefix<SUF>suffix<MID>` 的特殊 token 序列送入模型，让模型基于光标左右双向上下文预测中间内容。这解决了传统 LM 只看前文、无法感知后续代码（如已存在的闭合括号、后续函数调用）的问题。配合投机采样（speculative decoding）和 KV Cache 复用降低首 token 延迟，实现打字停顿即出补全的体验。
**功能6**：多信号补全触发与请求节流 - 客户端维护一套触发状态机：监听编辑器 debounce（停止输入约几百毫秒）、光标位置、语法上下文（是否在注释/字符串/新行）来决定是否发起请求；对高频击键做请求取消（in-flight request cancellation），后一次输入立即 abort 前一次未完成的推理请求，避免 GPU 资源浪费和陈旧结果闪烁。同时用轻量本地上下文缓存匹配，命中则零延迟返回，未命中才走服务端大模型。设计目标：把"是否要打扰用户"变成一个可调的成本/收益决策。
**功能7**：接受率遥测与在线质量闭环 - 每条补全记录其展示、部分接受（tab 逐词接受）、完整接受、被后续编辑覆盖等生命周期事件，回传形成 acceptance rate / retention rate 指标。这些信号既用于 A/B 实验对比不同模型和检索策略，也用作模型迭代的隐式反馈标签（被保留下来的代码是正样本，被立即删改的是负样本）。补全内容在展示前经过版权过滤器（public code matching）比对已知开源代码，命中可选择屏蔽或标注来源，规避许可证风险。
**功能8**：Agent Mode 与工具编排执行环 - Copilot Agent 具备自主的 plan-act-observe 循环：接到任务后规划步骤，通过工具集（读写文件、执行 shell 命令、运行测试、检索代码库、调用终端）实际操作代码库，读取命令输出/编译错误/测试失败作为反馈，迭代修复直到目标达成。关键设计：将编辑器能力、语言服务器诊断（LSP diagnostics）、终端 I/O 统一抽象为可调用工具，模型输出结构化 tool call；结合 checkpoint 机制允许回滚，人类在关键节点做 approve/reject，兼顾自动化与可控性。
**功能9**：模型路由与多模型调度层 - Copilot 后端是模型无关的路由层，针对不同任务把请求分派到不同模型：低延迟补全用专用小型快速模型，复杂对话/Agent 推理用大型前沿模型，代码审查另有专门配置。路由考虑任务类型、上下文长度、成本预算和用户所选模型偏好，并在模型不可用时做 fallback 降级。这层抽象让底层模型可热替换升级而不改变上层产品契约。

---

## Windsurf
**功能1**：IDE 事件流上下文 - 光标移动、文件开关、诊断、终端输出、git diff、索引变更作为事件流实时喂给 Agent，Cascade 是 IDE 原生 agent runtime 而非聊天面板。
**功能2**：三路混合代码索引 - Embedding 语义索引 + BM25 关键词 + AST 符号图三层并用，符号图补上纯向量会漏掉的定义、引用、调用关系。
**功能3**：动态上下文图裁剪 - 围绕当前任务维护相关性图，随编辑行为动态增删节点，控 token 同时保住跨文件关联，不把全项目塞 prompt。
**功能4**：Agent 验证循环 - read_file → 规划 → edit_file → 读 diagnostics → 继续修，用编译器和 linter 的真实报错做反馈信号驱动下一轮。
**功能5**：Operation 级编辑 - 修改以操作而非整文件覆盖形式应用，能和开发者实时编辑混合而不互相踩踏，是 Flow 不打断心流的工程前提。
**功能6**：符号图跨文件改动 - 改函数签名时通过 imports/exports 和 call graph 定位所有调用点，多文件同步修改。

---

## Bolt.new
**功能1**：WASM Node 运行时 - 把 Node.js 编译成 WebAssembly 跑在 Web Worker 里，配合模拟的进程、信号、管道、终端，`node`、`vite`、`next dev` 直接在浏览器标签页内执行，零服务器。
**功能2**：内存虚拟文件系统 - 用内存数据库实现 Node 所需全部 POSIX 文件语义，外套 Unix 文件系统接口，fs 调用落到浏览器内存。免去创建 VM、分配云盘、跑 Linux init，故启动极快。
**功能3**：浏览器内 npm install - npm CLI 在容器内运行，解压写入走虚拟 VFS，node_modules 用缓存、索引、虚拟化策略避免海量小文件完整复制。
**功能4**：端口代理与热预览 - 容器内 HTTP 服务代理到宿主 iframe，`server-ready` 回调驱动预览自动刷新，实现秒级改码即看。
**功能5**：Origin 级沙箱隔离 - 不用 Docker/gVisor，直接复用浏览器同源策略和 Worker 隔离做边界，配合 COOP/COEP 隔离头启用 SharedArrayBuffer 拿高性能。

---

## Kimi K3
**功能1**：四段调度架构 - Planner-Worker-Verifier-Synthesizer 分工，子 Agent 无权决定最终答案须过验证；有效规模为 1 Planner + 3~8 并发 Worker + 1~2 Verifier + 1 Synthesizer。
**功能2**：动态任务 DAG - 任务拆成可验证子任务构成有向图，按依赖调度并发，配合模型路由给不同子任务分不同规格的模型。
**功能3**：四级上下文分层 - L0 任务目标与验收标准 / L1 当前子任务内容 / L2 历史结论与工具结果 / L3 原始全文按需回溯，128K 用于跨文档关联而非每轮塞满。
**功能4**：claim/evidence 结构化记忆 - 记忆单元是 `{claim, evidence[], confidence, conflicts[], owner, status}` 结构化条目，天然支持冲突检测和答案强制绑定证据位置。
**功能5**：Map-Reduce-Verify 长文处理 - 多 Agent 并行读不同章节，汇总观点与冲突，关键结论回原文核查，避免多层摘要信息坍塌。
**功能6**：搜索控制器子循环 - 搜索计划 → 多查询并发 → 去重排序时间过滤 → 正文抽取 → 证据归因 → 识别缺口 → 改写再搜，是带反馈的子循环而非一次 function call。

---

## GitHub Copilot
**功能1**：FIM 双向补全 - 用 Fill-in-the-Middle 训练目标，将代码切成 prefix/middle/suffix 重排为 `<PRE>prefix<SUF>suffix<MID>` 送入模型，基于光标左右双向上下文预测中间内容，感知后续闭合括号与函数调用；配合投机采样和 KV Cache 复用降低首 token 延迟。
**功能2**：多信号触发节流 - 客户端触发状态机监听 debounce、光标位置、语法上下文决定是否发请求，对高频击键做 in-flight request cancellation 立即 abort 前次推理，本地上下文缓存命中则零延迟返回。
**功能3**：接受率遥测闭环 - 记录补全的展示、部分接受、完整接受、被覆盖等生命周期事件，形成 acceptance/retention 指标用于 A/B 实验和隐式反馈标签；展示前经 public code matching 版权过滤规避许可证风险。
**功能4**：Agent 工具编排环 - plan-act-observe 循环，将编辑器能力、LSP diagnostics、终端 I/O 统一抽象为可调用工具，模型输出结构化 tool call 操作代码库并读取命令输出/测试失败迭代修复；结合 checkpoint 回滚和人类 approve/reject 节点。
**功能5**：多模型路由调度 - 后端模型无关路由层，按任务类型、上下文长度、成本预算和用户偏好分派：低延迟补全用小型快速模型，复杂 Agent 推理用前沿大模型，并在模型不可用时 fallback 降级。

---

## Genspark

**功能1**：Spark Page 生成 - 不输出纯文本答案，而是产出带引用、可交互的结构化网页/轻量应用，含摘要、表格、卡片、时间线、图表与筛选排序模块

**功能2**：结构化中间表示 - LLM 不直接生成 HTML，先产出 page_type + sections 的 IR/JSON 中间层，再由模板/组件库/代码生成器渲染，保证页面稳定、可修改、可复用

**功能3**：多 Agent 研究流水线 - Planner 拆解任务后，多个 Search/Research Agent 并行检索网页、文档、新闻、价格、图片、PDF，Extraction Agent 抽取"实体→属性→数值→时间→来源"结构化事实

**功能4**：Critic 交叉验证 - 专门处理多来源冲突、过时信息、无来源断言、数字单位错误、引用与结论不匹配，是区别于普通搜索摘要的核心环节

**功能5**：Composer 内容编排 - 自动决定叙述顺序、哪些内容用表格/时间线呈现、哪些事实需突出，并生成标题摘要与 SEO 描述

**功能6**：QA 发布前检查 - 校验链接可用性、引用真实性、渲染正确性、内容去重、幻觉检测与移动端可读性

**功能7**：可重跑任务状态 - 任务被持久化，数据可刷新重跑，无需用户重新提问

---

## MACE

**功能1**：双层稀疏路由 EPE - 路由层按 `s=0.4·记忆分+0.3·专长匹配+0.3·权重` 打分，稀疏门控阈值 `θ=mean+k·std`（k=1）动态选人并钳制在 [2,6] 个 Agent；聚合层做 M=5 次 dropout（0.15 丢弃率）生成子集，按 `α·质量+(1-α)·多样性`（α=0.6，多样性=token Jaccard 距离）选优后加权合并，方差降至单 Agent 的 0.28×

**功能2**：CMDP 强化学习调度 - 维护 Q 表 + REINFORCE 基线，ε-greedy（ε=0.3 起、decay=0.995）平衡探索/利用，奖励 `R=质量-λ·成本+权重增益`（λ=0.1），用 advantage=reward-baseline 更新 Q 值，实现调度策略在线自学习

**功能3**：动态权重评审 - 每任务后按 `ω^(t+1)=(1-γ)ω^(t)+γ·ω_task`（γ=0.15）指数平滑更新，ω_task 由准确率/置信度/一致性/成本惩罚四维加权（α=0.25/0.25/0.2/0.15）合成并 clip 到 [0.05, 0.95]；每 100 任务触发 polyfit 斜率趋势诊断 + 3σ 偏差校正 + ReLU 非负调整

**功能4**：师徒式差异化学习 - 草稿置信度 < κ=0.6 或检索到低置信记录时触发提问，只向权重高于自己 +δ=0.15 的 Top-2 Agent 求助；答后 asker 的 sub_ask 分 +0.08、responder 的教学奖励 sub_mem +0.02，形成权重联动

**功能5**：三层遗忘记忆系统 - STM（200 条 FIFO）/LTM（高置信度晋升）/EPI（500 条情景记忆），综合评分 = 余弦相似度 × 层级权重 × 置信度 × 验证系数 × exp(-λΔt)（艾宾浩斯半衰期约 28.9 天）；共享门槛为置信度≥0.7 且访问≥2 次

**功能6**：异步并发 + 超时降级 - asyncio.Semaphore 控制并发数，单 Agent 超时不阻塞整体，失败自动扣权重，全败时降级为单 Agent 兜底

**功能7**：Mock 零成本验证 - MockAdapter(seed=42) 完全确定性输出，无需 API Key 即可跑通全链路，路由/聚合/调度三层公式化解耦、纯 Python 零 GPU 依赖、四个算法层全部白盒可改

---

## Lovable

**功能1**：OKLCH 感知均匀色彩系统 - 全站 205 个 CSS 变量弃用 hex/HSL，改用 `oklch(L C H)` 三通道。前景四级 `--fg-primary/secondary/tertiary/quaternary` 只改亮度不动色相（`.002 107` 恒定），保证任意明度下灰阶不偏色；语义色六类各自锁定色度（如 destructive 固定 `.2203 26.56`），换主题时只需平移 L 通道，对比度自动守恒

**功能2**：9 套品牌调色板热切换 - ocean/twilight/sapphire/flamingo 等每套提供 `--brand-{name}-primary` + `-foreground` 配对，值以裸 HSL 三元组存储（`224.6 88.2% 53.3%`）而非完整函数，可直接被 Tailwind 的 `hsl(var(--x) / <alpha-value>)` 插值，实现透明度与主题色正交组合

**功能3**：五层复合表面阴影引擎 - `--shadow-surface-xs → xl` 每档由 5 层 box-shadow 叠加（描边层 + 表面基色层 + `calc(var(--border-default)*2)` 双倍扩散暗环 + 1px 硬边高光 + 负 spread 柔化投影），所有偏移用 `calc(Npx + var(--border-default))` 补偿边框宽度，边框变粗时阴影不被吞掉，xl 档扩散到 `24px 24px -12px`

**功能4**：Glow 交互态发光令牌 - 为每个语义色预生成 hover/pressed 两级发光变量，透明度阶梯固定 `.16`/`.24`（`--glow-accent-hover: oklch(52.43% .2396 264.41/.16)`）。交互反馈不改背景色，而是叠加同色相低透明外发光，暗色模式下不因加深背景丢失层次

**功能5**：LightningCSS 双值互斥暗色模式 - 用 `--lightningcss-light: ""` 与 `--lightningcss-dark: initial` 一对哨兵变量做条件开关，`initial` 触发回退链、空字符串命中，实现零 JS、零媒体查询重复声明的主题分支，编译期由 Rust 版 LightningCSS 展开，构建速度远超 PostCSS 链路

**功能6**：Base UI + Tailwind 无头架构 - DOM 中 `#base-ui-_r_xxx_` ID 前缀表明交互层用 MUI 的 Base UI（只给行为与 a11y、不给样式），视觉层完全由 token + Tailwind 原子类接管，AI 生成组件既有正确的键盘导航/焦点陷阱/ARIA，又能被设计系统 100% 重绘

**功能7**：flock.js 敏感字段脱敏 - 每个发布站注入的 `~flock.js` 内置 22 词黑名单（password/token/email/credit_card/order_id…），上报前对 JSON 执行 `replaceAll(/("key"):(".+?"|\d+)/mgi, '$1:"********"')`，键名匹配即值替换，隐私数据离开浏览器前已抹除

**功能8**：密码学安全 Session - 用 `crypto.getRandomValues` 逐位异或生成 UUID v4，三存储降级写入 cookie(`Max-Age=1800; secure`)/localStorage/sessionStorage，后两者附带 `expiry: now+18e5` 手动过期戳，实现 30 分钟滑动窗口

**功能9**：反爬熔断上报过滤 - 上报前检查 `window.__nightmare || navigator.webdriver || window.Cypress` 三个自动化指纹直接 return，再对 `navigator.userAgent.length > 500` 异常长 UA 熔断丢弃，从源头保证分析数据不被爬虫和 E2E 测试污染

**功能10**：History API 劫持式 SPA 追踪 - 包裹重写原始 `history.pushState`（`P.apply(this,arguments); y()`）并监听 `popstate`/`hashchange`，使 React Router 无刷新跳转也产出 `page_hit`；上报走 XHR POST 到 Tinybird `/v0/events`，支持自建 endpoint 三级回退（自定义 URL → 代理 `/api/tracking` → 官方域）

**功能11**：Web Vitals 全量 RUM 采集 - 内联 Google 官方 web-vitals 源码采集 CLS/FCP/LCP/INP/TTFB 五项，按 good/needs-improvement/poor 三档阈值评级随事件上报，使每个生成站点开箱即带真实用户性能监控，无需第三方 SDK

---

## Replit

**功能1**：goval 三层容器内核 - `lore` 集群编排（`CreateRepl`/`TransferRepls`/`TakedownRepl`/`GetReplConnectionInfo`）+ `conman` 实例管理器 + 容器内 `pid1` 作为 1 号 init 进程（`pid1Config`/`pid1RefreshSecrets` 托管进程树与密钥热刷新）。前端 JS 中 goval 出现 4518 次、conman 37 次、pid1 47 次——全自研底座，不租第三方沙箱，这是与 Manus 等租用 E2B 产品的根本分野

**功能2**：replspace 容器内 RPC 通道 - Agent 与 IDE 不走 SSH/HTTP，而是专用 RPC：`replspaceApiOpenFile` 开文件、`ShellTracker` 管 shell 会话、`SSHTokenGet`/`GetGitHubToken` 下发凭证；命令主通道 `Command`（引用 191 次）+ `Exec`/`ExecInfo`，文件侧 `File`/`Files`/`FileEvent`/`Transfer`。单一二进制协议同时承载执行、文件、凭证，省掉多协议栈延迟与鉴权分裂

**功能3**：OT 实时协同内核 - `OTPacket`/`OTCursor`/`OTStatus`/`OTFetch` 是完整 Operational Transform 实现（非 CRDT 亦非文件锁）。人类与多个 AI 子 agent 可同时编辑同一文件而不冲突覆盖，agent 的 patch 与用户键入被变换到同一因果序上——这是"边看 agent 写边自己改"的底层前提

**功能4**：三位一体 Checkpoint 回滚 - `CreateCheckpointResponse.commit_sha` 表明每个检查点是一次真实 git commit，`RestoreCheckpointRequest.rollback_database` 使数据库同步回退，再叠加容器层 `FSSnapshot`/`FSSnapshotEvent` + `TimeTravelConfig` 文件系统快照。代码、数据、文件系统三份状态一致回滚，而非只 revert 代码留下脏库

**功能5**：Nix 声明式环境构建 - 装包走 `NixPackageAdd/Remove/Search/List` + `NixModule`/`NixChannel`，声明写在 `replit.nix`，`resetNixFilesystem` 一键重建纯净环境（Nix 出现 602 次），配合 `.replit`（run 命令/端口/语言/packager 配置）。环境可版本化、可复现、可回滚，Agent 改坏依赖不污染不可逆

---

