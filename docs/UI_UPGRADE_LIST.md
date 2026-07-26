# Black God UI 升级清单

> 基于24个AI产品192个能力逆向 · opus4.8整理 · 2026-07-26

## P0

- [ ] **对话页：流式打字机 + 光标闪烁** | 来自：ChatGPT/Claude iOS | 实现：JS 按 token/字符分帧 append 文本，末尾 `▋` 光标用 `@keyframes blink` 0.8s；配合 `content-visibility` 减少重排 | 效果：消息实时吐字，感知延迟↓，专业感↑

- [ ] **对话页：消息骨架屏/思考态** | 来自：Perplexity/v0 | 实现：等待首 token 时显示三点脉冲 `···`（`@keyframes` 交替 opacity）或翡翠绿 shimmer 骨架条（`linear-gradient` + `background-position` 位移动画）| 效果：消除"卡死"焦虑

- [ ] **执行日志：分步展开 + 状态图标** | 来自：Devin/Manus/Cline | 实现：每步用 `<details>` 或 JS 折叠，状态点用色（灰=待执行/翡翠脉冲=进行/绿√=完成/红=失败），进行中步骤加 `box-shadow` glow | 效果：Agent 执行过程可视化，信任感↑

- [ ] **发送按钮：状态机（发送/生成中/停止）** | 来自：ChatGPT/Cursor | 实现：三态切换，生成中变方形 stop 图标 + 环形 loading（`stroke-dasharray` 旋转），点击可中断 | 效果：符合 Agent 交互心智，避免误触

- [ ] **全局：无障碍焦点环 + prefers-reduced-motion** | 来自：Cursor/Linear 系 | 实现：`:focus-visible` 用已有 glow-focus 令牌；`@media (prefers-reduced-motion)` 降级所有动画为 opacity | 效果：可访问性合规，晕动症用户友好

- [ ] **对话页：代码块渲染 + 复制按钮** | 来自：v0/Cursor/Replit | 实现：等宽字体 + 深色代码卡（比气泡更深 `#070C09`），右上角悬浮复制按钮，复制后翡翠√反馈 2s | 效果：技术输出可读可用

## P1

- [ ] **神枢主页：轨道随状态变速** | 来自：Manus/Devin | 实现：CSS 变量 `--orbit-speed` 由 JS 按状态（idle 慢/thinking 快/error 抖动）注入，`animation-duration: var()` | 效果：主页即状态仪表盘

- [ ] **对话页：命令面板 ⌘K / 长按唤起** | 来自：Cursor/Linear | 实现：全屏毛玻璃层（`backdrop-filter: blur`）+ 模糊搜索列表 + 键盘导航，翡翠高亮选中项 | 效果：快速切模型/模式/清空，效率工具感

- [ ] **能力折叠：Bento 网格卡片** | 来自：v0/Lovable | 实现：能力项改 `grid` 不等宽卡片，hover 抬升（已有 shadow-md→lg + glow-hover），图标微动 | 效果：能力一览更有层次

- [ ] **对话页：引用/来源折叠卡** | 来自：Perplexity | 实现：AI 回答下方 chip 列表（编号 + 标题），点击展开来源详情，chip 用描边翡翠样式 | 效果：可溯源，降低幻觉焦虑

- [ ] **模式切换：滑块指示器动画** | 来自：Cline/Operator（plan/act 切换）| 实现：分段控件下方翡翠 pill 用 `transform: translateX` + spring 曲线滑动 | 效果：模式切换有物理反馈

- [ ] **消息气泡：入场错峰动画** | 来自：Lovable/Manus | 实现：新气泡 `transform: translateY(8px) + opacity` 用 ease-out-quart 入场，200ms | 效果：对话流更顺滑

- [ ] **设置页：分组卡 + 即时反馈** | 来自：Claude iOS/Linear | 实现：列表分组圆角卡，开关切换用 spring，改动后短暂翡翠底色高亮该行 | 效果：设置操作有确认感

- [ ] **登录页：orb 呼吸 + 输入聚焦联动** | 来自：Lovable glow | 实现：owner 密码框聚焦时 orb glow 增强（JS 加 class 提升 `--glow` 强度），错误时 orb 红闪抖动 | 效果：登录仪式感 + 状态反馈

- [ ] **全局：Toast/通知系统** | 来自：Replit/v0 | 实现：右上/顶部滑入 toast（成功=翡翠/错误=红/信息=中性），`transform + opacity` spring 入场，3s 自动收 | 效果：操作反馈统一

- [ ] **对话页：可中断 + 重新生成/编辑** | 来自：ChatGPT/Claude | 实现：AI 消息 hover 出现工具条（重生成/复制/编辑），翡翠图标按钮组 | 效果：对话可控可修正

## P2

- [ ] **神字 orb：粒子/流光 canvas** | 来自：Manus/Perplexity | 实现：轻量 canvas 粒子沿 orb 轨迹流动，或纯 CSS `conic-gradient` 旋转流光遮罩 | 效果：品牌视觉记忆点

- [ ] **主页：轨道节点可点击 tooltip** | 来自：Devin/CrewAI（多 agent 编排）| 实现：轨道上的能力节点 hover/tap 弹出 tooltip 卡，描边翡翠气泡带小三角 | 效果：可交互的仪表盘

- [ ] **对话页：滚动到底部悬浮按钮** | 来自：ChatGPT | 实现：非底部时显示下箭头浮钮，`IntersectionObserver` 控制显隐，翡翠圆钮 | 效果：长对话导航

- [ ] **全局：主题微调（辉光强度/密度）** | 来自：Cursor 设置 | 实现：设置页滑块调 CSS 变量 `--glow-intensity` / 列表密度，`localStorage` 持久化 | 效果：个性化

- [ ] **执行日志：耗时/token 计量条** | 来自：Devin/CrewAI | 实现：每步右侧显示耗时，底部翡翠进度条动画累计 | 效果：性能透明

- [ ] **气泡：Markdown 富文本渲染** | 来自：v0/Perplexity | 实现：支持列表/表格/引用块样式，表格深色描边翡翠表头 | 效果：结构化输出美观

- [ ] **全局：页面切换转场** | 来自：Linear/Lovable | 实现：Tab 切换用 fade+slide（`transform` 微位移），共享元素避免生硬跳变 | 效果：App 高级感

- [ ] **登录页：注册成功 → 主页 orb 汇聚转场** | 来自：Manus 引导流 | 实现：登录 orb 缩放位移过渡到主页轨道中心，一镜到底 | 效果：入场仪式高潮

- [ ] **对话页：空状态引导卡** | 来自：v0/ChatGPT | 实现：首次进入显示建议 prompt chips，点击填入输入框，翡翠描边卡片 | 效果：降低启动门槛

- [ ] **全局：haptic 触觉反馈钩子** | 来自：Claude iOS | 实现：关键操作调 `navigator.vibrate` 或 WKWebView haptic 桥，配合视觉反馈 | 效果：原生 App 手感

---

**建议落地顺序**：P0 全部 → P1 前 5 条（命令面板/状态变速/来源卡/模式滑块/toast）→ 其余按资源补。P0 直接决定"像不像专业 Agent 产品"，P1 决定"好不好用"，P2 决定"记不记得住"。