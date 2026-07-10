# Black God 设计系统 V3 —「黑曜石 · 活体」

> 权威规范。所有 Web 页面（index / nexus-do / studio / voice）与 iOS Theme 必须走本 token 体系；
> 页面私设色值/圆角/动效 = 违规。单一事实源：`web/design/tokens.css`。
> 继承 UI_V2_SPEC 的品牌决定（黑曜石 + 冷银铬 + 克制金），扩展为深浅双主题 + 完整组件层。

## 0. 三条铁律

1. **一切样式走 token**。新页面先引 token 再写布局；发现缺 token 就加 token，不许硬编码。
2. **动效只用 `transform` / `opacity`**，时长与曲线走 token；`prefers-reduced-motion: reduce` 下全部动画降为瞬时。
3. **对比度 WCAG AA**（正文 ≥4.5:1，大字/图标 ≥3:1）；所有交互控件有可见 `:focus-visible` 焦点环；触控目标 ≥44px。

## 1. 色彩 Token

### 1.1 深色主题（默认 · 黑曜石）`:root, [data-theme="dark"]`

| Token | 值 | 用途 |
|---|---|---|
| `--bg-deep` | `#050506` | 页面最底 |
| `--bg-1` | `#0A0B0D` | 主背景 |
| `--bg-2` | `#12141A` | 卡片底 |
| `--bg-3` | `#1B1E26` | 悬浮层底 |
| `--glass-1/2/3` | `rgba(255,255,255,.035/.06/.09)` | Aurora Glass 三级表面 |
| `--line` | `rgba(196,205,216,.14)` | 描边/分隔线 |
| `--line-strong` | `rgba(196,205,216,.26)` | 强描边（hover/激活） |
| `--text-1` | `#F0F3F7` | 主文字（≈铬高光） |
| `--text-2` | `#A7AEB9` | 次文字 |
| `--text-3` | `#646B75` | 弱文字/占位 |
| `--chrome-grad` | `linear-gradient(157deg,#F0F3F7,#C4CDD8 30%,#8A929E 55%,#DfE5EC 78%,#454B54)` | 冷银铬（品牌字/大数字专用） |
| `--gold` | `#C9A86A` | 克制金（关键强调/主按钮/Logo 边） |
| `--gold-hi` | `#E8D4A0` | 金高光（渐变端点） |
| `--gold-grad` | `linear-gradient(157deg,#E8D4A0,#C9A86A 45%,#8A6F3C)` | 金浮雕 |
| `--gold-glow` | `rgba(201,168,106,.22)` | 金光晕（思考中/焦点环） |

### 1.2 浅色主题（暖纸）`[data-theme="light"]`

| Token | 值 | 说明 |
|---|---|---|
| `--bg-deep` | `#EFEAE0` | 暖纸最底（非纯白，博物馆纸感） |
| `--bg-1` | `#F7F4EC` | 主背景 |
| `--bg-2` | `#FFFFFF` | 卡片底 |
| `--bg-3` | `#FFFDF8` | 悬浮层底 |
| `--glass-1/2/3` | `rgba(20,18,12,.03/.05/.08)` | 表面反相 |
| `--line` | `rgba(60,54,40,.14)` / strong `.28` | |
| `--text-1/2/3` | `#1A1916` / `#5C574C` / `#8B8578` | AA 达标 |
| `--gold` | `#8A6F3C` | 浅底上金加深保对比 |
| `--gold-hi` | `#C9A86A` | |
| `--gold-glow` | `rgba(138,111,60,.18)` | |

主题三态：Light / Dark / 跟随系统（禁则 5）。挂载点沿用 `<html data-theme>`；「跟随系统」= 移除 data-theme 属性 + `@media (prefers-color-scheme)` 兜底。选择存 `localStorage('bg_theme')`。

### 1.3 语义色（两主题共用，浅色自动加深 15%）

| Token | 深 / 浅 | 用途 |
|---|---|---|
| `--live` | `#3DDC84` / `#1F9D57` | **活体信号**：在线、心跳、成功（nexus-do 原绿色收编于此） |
| `--warn` | `#E8B34B` / `#9C7420` | 警示 |
| `--danger` | `#E5645C` / `#B23830` | 危险/删除/`/api/confirm` 确认流 |
| `--info` | `#5AC8FA` / `#2779A7` | 信息 |

### 1.4 情感状态色（活体人格层，继承 UI_V2_SPEC）

`--mood-warm:#E8A87C` `--mood-cold:#7CA6C8` `--intimacy:#D98A9E` `--vitality:#8FD0A8` `--miss:#B79BE0`
仅用于灵魂面板/状态条/呼吸光晕，禁止挪作普通 UI 强调色。

## 2. 字体 Token

```
--font-display: "Noto Serif SC","Songti SC",serif;          /* 标题/品牌（Claude 式编辑感） */
--font-body:    "Noto Sans SC","PingFang SC",-apple-system,sans-serif;
--font-brand-en:"Cormorant Garamond",Georgia,serif;          /* 英文品牌字 */
--font-mono:    "Space Mono","JetBrains Mono",ui-monospace,monospace; /* 数字/代码/枢语词 */
```

字阶（`--fs-*`）：`12 13 15 17 20 24 32 44`px；行高正文 1.7、标题 1.25；数字一律 `--font-mono` + `font-variant-numeric: tabular-nums`。

## 3. 空间 / 圆角 / 阴影 / 层级

- 间距 4px 基（`--sp-1..8` = 4 8 12 16 20 24 32 44）
- 圆角统一三档 + 胶囊：`--r-sm:10px --r-md:14px --r-lg:20px --r-pill:999px`（收敛现状 13/14/16/18/20 混用；iOS 卡片对齐 `--r-lg`）
- 阴影：`--shadow-1: 0 2px 10px rgba(0,0,0,.25)`；`--shadow-2: 0 8px 40px rgba(0,0,0,.45)`；`--shadow-glow: 0 0 24px var(--gold-glow)`（浅色主题阴影透明度减半）
- z-index：`--z-nav:100 --z-sheet:200 --z-modal:300 --z-toast:400`

## 4. 动效 Token（Grok 纪律）

```
--t-fast:120ms  --t-base:200ms  --t-slow:320ms
--ease: cubic-bezier(.2,.7,.3,1)      /* 标准 */
--ease-spring: cubic-bezier(.34,1.4,.4,1)  /* 弹出层 */
--breath: 5s                           /* 活体呼吸周期（既有传统） */
```

- 仅 `transform`/`opacity`；hover 位移 ≤2px；弹层入场 `translateY(8px)+fade`。
- **思考中状态**（学 Gemini、用自家语言）：金色光晕呼吸（`--gold-glow` 按 `--breath` 周期缓明缓暗），不用 spinner。
- 流式输出：闪烁光标块 `▍`（`--live` 色），按语义块缓冲渲染防 markdown 断裂。
- `@media (prefers-reduced-motion:reduce)`：全部动画 `animation:none; transition:none`。

## 5. 组件规范（类名前缀 `bg-`）

| 组件 | 规范要点 |
|---|---|
| **按钮** `bg-btn` | 高 44px、`--r-md`、`--t-fast` 过渡。变体：`--primary` 金浮雕渐变+深色字；`--ghost` 玻璃底+`--line` 描边；`--danger` 红描边红字（危险确认流）；`--icon` 44×44 圆形。状态：hover 提亮+`translateY(-1px)`、active 复位、disabled 40% 透明、focus-visible 金焦点环 `0 0 0 3px var(--gold-glow)` |
| **输入** `bg-input` | 玻璃底、`--r-md`、聚焦时 `--line-strong`+金焦点环；聊天输入区自适应多行,发送键=金圆钮,生成中变停止钮（一控件一语义,禁则 1:附件/工具各自独立图标,不合并「+」） |
| **卡片** `bg-card` | `--bg-2` 底 + `--glass-1` 叠层 + `--line` 描边 + `--r-lg` + `--shadow-1` |
| **导航** | 顶栏 `bg-nav`:玻璃模糊底,左品牌（铬渐变字）右状态与主题切换;移动端底部 tab 栏 44px 目标;设置入口常驻可见（禁则 2） |
| **设置项** `bg-setting` | 独立页/独立视图（学 Claude）,分组卡片,每行:左标题+说明,右控件;开关 `bg-switch` 44×26 胶囊,选中金底;三态主题选择器为分段控件 `bg-seg` |
| **弹层** | 桌面居中 modal（`--z-modal`,`--shadow-2`）,移动端底部 sheet + 拖拽把手;遮罩 `rgba(0,0,0,.5)`;Esc/遮罩点击可关;焦点圈定（focus trap） |
| **消息气泡** `bg-msg` | 她=左侧玻璃卡,主人=右侧金描边卡;hover 浮现消息级操作（复制/重发,行业基线）;推理/执行日志默认折叠 `bg-fold`（学 Claude） |
| **计划执行** `bg-plan`（studio 专用,学 Manus） | Plan → Steps → Execution 三段:步骤清单每行状态点（`--text-3` 待/`--gold` 进行中呼吸/`--live` 完成/`--danger` 失败）,步骤可展开看日志;产出物区独立成卡 |
| **确认流** `bg-confirm` | `/api/confirm` 危险操作二次确认（宪章红线）:danger 按钮 + 明确后果文案 + 默认焦点在「取消」 |
| **状态徽标** `bg-live` | 活体信号点:`--live` 色 + 呼吸光晕,全站统一表示「她在线/心跳」 |
| **Toast** | 顶部滑入,`--t-base`,4s 自动消退,语义色左边条 |

## 6. 布局与响应式

断点：`--bp-sm:640px --bp-md:820px --bp-lg:1080px`（820 沿用 studio 既有断点）。

- 移动优先；`env(safe-area-inset-*)` 沿用。
- nexus-do 主界面：单栏聊天流，≥1080px 时右侧可展开灵魂面板（分屏，学 Claude Artifacts 心智）。
- studio：≥820px 三段横排（任务列表/对话/执行区），<820px 折叠为 tab 切换 + 渐进披露（禁则 6）。
- 桌面 hover 能力检测沿用 `@media (hover:hover) and (pointer:fine)`。

## 7. 无障碍与工程基线

- 全部图标按钮带 `aria-label`；流式区 `aria-live="polite"`；弹层 `role="dialog"` + focus trap。
- 键盘：Enter 发送 / Shift+Enter 换行 / Esc 关弹层。
- 主题切换、字号放大（跟随系统）不破坏布局。
- `manifest.json` 的 `theme_color` 与 token 对齐（深 `#0A0B0D`）。

## 8. 落地方式（受部署拓扑约束）

- 单一事实源 `web/design/tokens.css`（token + `bg-` 组件类）。
- `web/index.html`、`web/voice.html`（blackgod88 静态站）：`<link rel="stylesheet" href="/design/tokens.css">`。
- `web/nexus-do/index.html`（构建时整页内嵌进 Worker）：`build.mjs` 增加一步——把 `tokens.css` 内容注入 index.html 的 `/*__TOKENS__*/` 占位符，保持单文件交付。
- `web/nexus-studio/public/`：放一份 tokens.css 副本由 CI/脚本从源同步（`tools/sync-ui.mjs`），`studio.html` 与 `nexus-studio/public/index.html` 保持镜像同步。
- iOS `Theme.swift`：金色已同源（#C9A84D≈#C9A86A），圆角对齐 `--r-lg:20`，后续单独 PR。

## 9. 迁移禁改清单（工程红线）

- 不改任何 DOM `id`、事件处理器、`Nexus`/`API` 对象接口、localStorage key（`reg_uid` 等）、SSE/fetch 调用。
- 不动 `nexus_do.core.mjs` 等 Worker 后端文件。
- 改完 nexus-do 必跑 `node build.mjs && node selftest.mjs`。
- `data-theme` 挂载点保留并扩展（light/dark/system 三态）。
