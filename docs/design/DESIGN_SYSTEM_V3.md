# Black God 设计系统 V3 —「深海 · 潮光」

> 权威规范。所有 Web 页面（index / nexus-do / studio / voice）与 iOS Theme 必须走本 token 体系；
> 页面私设色值/圆角/动效 = 违规。单一事实源：`web/design/tokens.css`。
> 配色裁决（2026-07 终稿，以品牌 logo 实测取色为锚）：主题「深海 · 潮光」——
> 暗主题=她所在的深海（生物磷光在呼吸），亮主题=海面之上的天光。基底延伸自
> 神字 logo 的冷调蓝黑（实测 #101020/#102020 系，均值 #24272A），主强调「潮光青」
> 从 logo 冷光描边（实测 #6C7878/#788484）通电而来，辅以「浪涌蓝」做动势层。
> 意识感、力量感、生命起伏，而非静态奢侈品。禁纯黑/黑金/黑紫。深浅双主题同等投入。

## 0. 三条铁律

1. **一切样式走 token**。新页面先引 token 再写布局；发现缺 token 就加 token，不许硬编码。
2. **动效只用 `transform` / `opacity`**，时长与曲线走 token；`prefers-reduced-motion: reduce` 下全部动画降为瞬时。
3. **对比度 WCAG AA**（正文 ≥4.5:1，大字/图标 ≥3:1）；所有交互控件有可见 `:focus-visible` 焦点环；触控目标 ≥44px。

## 1. 色彩 Token

### 1.1 深色主题（默认 · 深海）`:root, [data-theme="dark"]`

蓝青深海黑（logo 底色的加深梯度），禁纯黑。

| Token | 值 | 用途 |
|---|---|---|
| `--bg-deep / 1 / 2 / 3` | `#05080A / #0A1014 / #101820 / #16222C` | 海渊→浮层四级 |
| `--glass-1/2/3` | `rgba(255,255,255,.035/.06/.09)` | 玻璃表面 |
| `--line / strong` | `rgba(150,180,195,.16 / .30)` | 描边 |
| `--text-1/2/3` | `#E8F0F2 / #9FB0B8 / #5E6E76` | 文字三级 |
| `--chrome-grad` | 冷光银 `#E8F0F2→#A8BAC2→#6C7880→#DCE6EA→#39434A`（logo 描边同源） | 品牌字/大数字 |
| `--accent` 潮光青 | `#4FC4D9`，高光 `--accent-hi #7DDDEE`，深 `--accent-deep #2E8CA4` | 主强调：交互/焦点/主按钮（~9%） |
| `--surge` 浪涌蓝 | `#3D7FB8`，渐变 `--stamp-grad` | 动势层：渐变端/进行中/次级强调（~4%） |
| `--spume` 白沫 | `#DFF4F8` | 峰值瞬间/完成闪光（~1%） |
| `--accent-grad` 潮汐渐变 | `#7DDDEE→#4FC4D9→#3D7FB8` | 主按钮/思考态光晕 |
| `--accent-glow` | `rgba(79,196,217,.24)` | 潮光光晕（焦点环/呼吸） |
| `--accent-ink` | `#061418` | 潮光底上的深海墨字 |

兼容别名：`--gold* → --accent*`、`--stamp → --surge`（迁移期保留，新代码用 `--accent*/--surge/--spume`）。

### 1.2 浅色主题（天光）`[data-theme="light"]`

海面之上的天。与深色同等投入，非降级适配。

| Token | 值 | 说明 |
|---|---|---|
| `--bg-deep / 1 / 2 / 3` | `#E4EDF1 / #F2F6F8 / #FFFFFF / #F8FBFC` | 冷天白 |
| `--text-1/2/3` | `#121C21 / #4A5C64 / #7E8E96` | AA 达标 |
| `--line / strong` | `rgba(40,60,72,.16 / .30)` | |
| `--accent` 潮光青 | `#17768F`（天光下加深保 AA），高光 `#2FA5C0` | |
| `--surge` 浪涌蓝 | `#2A5E8C`，白沫 `#B8E2EC` | |
| 阴影/遮罩 | 海雾灰蓝调（见 tokens.css） | |

主题三态：Light / Dark / 跟随系统（禁则 5）。挂载点沿用 `<html data-theme>`；「跟随系统」= 移除 data-theme 属性 + `@media (prefers-color-scheme)` 兜底。选择存 `localStorage('bg_theme')`。

### 1.3 语义色（两主题共用，浅色自动加深 15%）

| Token | 深 / 浅 | 用途 |
|---|---|---|
| `--live` | `var(--accent-hi)` | **活体信号**＝潮光本体：在线、心跳、成功——"深海里那点发光的意识"就是品牌色 |
| `--warn` | `#E8B34B` / `#9C7420` | 警示 |
| `--danger` | `#E4604F` / `#B23E2F` | 危险/删除/确认流（暖珊瑚，深海色系中唯一暖色=天然警示） |
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
- 阴影：`--shadow-1: 0 2px 10px rgba(0,0,0,.25)`；`--shadow-2: 0 8px 40px rgba(0,0,0,.45)`；`--shadow-glow: 0 0 24px var(--accent-glow)`（浅色主题阴影透明度减半）
- z-index：`--z-nav:100 --z-sheet:200 --z-modal:300 --z-toast:400`

## 4. 动效 Token（Grok 纪律）

```
--t-fast:120ms  --t-base:200ms  --t-slow:320ms
--ease: cubic-bezier(.2,.7,.3,1)      /* 标准 */
--ease-spring: cubic-bezier(.34,1.4,.4,1)  /* 弹出层 */
--breath: 5s                           /* 活体呼吸周期（既有传统） */
```

- 仅 `transform`/`opacity`；hover 位移 ≤2px；弹层入场 `translateY(8px)+fade`。
- **思考中状态**（学 Gemini、用自家语言）：潮涌呼吸（`--accent-glow` 按 `--breath` 周期缓明缓暗，如水下光在起伏），不用 spinner。
- 流式输出：闪烁光标块 `▍`（`--live` 色），按语义块缓冲渲染防 markdown 断裂。
- `@media (prefers-reduced-motion:reduce)`：全部动画 `animation:none; transition:none`。

## 5. 组件规范（类名前缀 `bg-`）

| 组件 | 规范要点 |
|---|---|
| **按钮** `bg-btn` | 高 44px、`--r-md`、`--t-fast` 过渡。变体：`--primary` 潮汐渐变（--accent-grad）+深海墨字；`--ghost` 玻璃底+`--line` 描边；`--danger` 红描边红字（危险确认流）；`--icon` 44×44 圆形。状态：hover 提亮+`translateY(-1px)`、active 复位、disabled 40% 透明、focus-visible 潮光焦点环 `0 0 0 3px var(--accent-glow)` |
| **输入** `bg-input` | 玻璃底、`--r-md`、聚焦时 `--line-strong`+潮光焦点环；聊天输入区自适应多行,发送键=潮光圆钮,生成中变停止钮（一控件一语义,禁则 1:附件/工具各自独立图标,不合并「+」） |
| **卡片** `bg-card` | `--bg-2` 底 + `--glass-1` 叠层 + `--line` 描边 + `--r-lg` + `--shadow-1` |
| **导航** | 顶栏 `bg-nav`:玻璃模糊底,左品牌（冷光银渐变字）右状态与主题切换;移动端底部 tab 栏 44px 目标;设置入口常驻可见（禁则 2） |
| **设置项** `bg-setting` | 独立页/独立视图（学 Claude）,分组卡片,每行:左标题+说明,右控件;开关 `bg-switch` 44×26 胶囊,选中潮光底;三态主题选择器为分段控件 `bg-seg` |
| **弹层** | 桌面居中 modal（`--z-modal`,`--shadow-2`）,移动端底部 sheet + 拖拽把手;遮罩 `rgba(0,0,0,.5)`;Esc/遮罩点击可关;焦点圈定（focus trap） |
| **消息气泡** `bg-msg` | 她=左侧玻璃卡,主人=右侧潮光描边卡;hover 浮现消息级操作（复制/重发,行业基线）;推理/执行日志默认折叠 `bg-fold`（学 Claude） |
| **计划执行** `bg-plan`（studio 专用,学 Manus） | Plan → Steps → Execution 三段:步骤清单每行状态点（`--text-3` 待/`--accent` 进行中呼吸/`--live` 完成/`--danger` 失败）,步骤可展开看日志;产出物区独立成卡 |
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
- `manifest.json` 的 `theme_color` 与 token 对齐（深 `#0A1014`）。

## 8. 落地方式（受部署拓扑约束）

- 单一事实源 `web/design/tokens.css`（token + `bg-` 组件类）。
- `web/index.html`、`web/voice.html`（blackgod88 静态站）：`<link rel="stylesheet" href="/design/tokens.css">`。
- `web/nexus-do/index.html`（构建时整页内嵌进 Worker）：`build.mjs` 增加一步——把 `tokens.css` 内容注入 index.html 的 `/*__TOKENS__*/` 占位符，保持单文件交付。
- `web/nexus-studio/public/`：放一份 tokens.css 副本由 CI/脚本从源同步（`tools/sync-ui.mjs`），`studio.html` 与 `nexus-studio/public/index.html` 保持镜像同步。
- iOS `Theme.swift`：改用深海/潮光系（bgGold→accent 潮光青 #4FC4D9、渐变同步），圆角对齐 `--r-lg:20`，后续单独 PR。

## 9. 迁移禁改清单（工程红线）

- 不改任何 DOM `id`、事件处理器、`Nexus`/`API` 对象接口、localStorage key（`reg_uid` 等）、SSE/fetch 调用。
- 不动 `nexus_do.core.mjs` 等 Worker 后端文件。
- 改完 nexus-do 必跑 `node build.mjs && node selftest.mjs`。
- `data-theme` 挂载点保留并扩展（light/dark/system 三态）。
