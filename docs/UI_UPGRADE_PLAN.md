# Black God 前端升级规划

> opus5 规划 · 2026-07-26

# Black God 前端升级规划 v1

## 0. 依赖拓扑（决定顺序的唯一依据）

```
                 ┌─ [1] OKLCH Token 底座 ────► [8] 9套调色板热切换
视觉层           │
                 └─ [2] 流式打字机 ──► [3] CoT折叠 ──┐
                                                      ├─► [10] Diff块
消息块渲染协议 ◄──────────────────────────────────────┼─► [9] 计划层
  (BlockRenderer)                                     ├─► [11] 三元对齐
                                                      └─► [12] 证据图

                 ┌─ [13] Session UUID ─┐
遥测层           │                      ├─► [4] Web Vitals ─┐
                 └─ [5] History劫持 ───┘                    ├─► [6] 脱敏 ─► [7] 熔断上报
                                                             │
                                                     (脱敏/熔断必须在出口，最后接)

架构层           [14] Base UI 无头 ── 独立分支，不阻塞任何人
```

**两个关键判断：**

1. **9/10/11/12 不是四个功能，是一个功能**——它们都是"结构化消息块"。必须先定 `BlockRenderer` 协议，否则会写四套互不兼容的渲染代码。这条是本规划最重要的一句话。
2. **6/7 不是独立能力，是遥测管道的两级中间件**。单独做没意义，必须挂在 4/5 的出口上。

---

## 排序总表

| # | 能力 | 批次 | 改动面 | 工时 | 感知收益 | 前置 |
|---|------|------|--------|------|---------|------|
| 1 | OKLCH Token 底座 | **第一批** | 纯CSS | 1.5h | ★★★☆☆ | — |
| 2 | 流式打字机 | **第一批** | 纯JS | 1h | ★★★★★ | — |
| 13 | Session UUID | **第一批** | 纯JS | 0.3h | ☆ (基建) | — |
| 3 | CoT 折叠 | **第一批** | HTML+CSS+JS | 1.5h | ★★★★★ | 2 |
| 0* | BlockRenderer 协议 | **第一批** | JS | 1.5h | ☆ (基建) | 2,3 |
| 8 | 9套调色板热切换 | 第二批 | CSS+JS | 1h | ★★★★☆ | 1 |
| 10 | Diff 块 | 第二批 | JS+CSS | 2h | ★★★★☆ | 0* |
| 4 | Web Vitals RUM | 第二批 | 纯JS | 1.5h | ☆ (基建) | 13 |
| 5 | History 劫持 SPA 追踪 | 第二批 | 纯JS | 0.5h | ☆ (基建) | 13 |
| 6 | flock.js 脱敏 | 第二批 | 纯JS | 1h | ☆ (合规) | 4,5 |
| 7 | 反爬熔断上报过滤 | 第二批 | 纯JS | 1h | ☆ (稳定) | 6 |
| 9 | 可编辑计划层 | 第三批 | HTML+CSS+JS | 3h | ★★★★☆ | 0* |
| 11 | 断言-证据-来源三元 | 第三批 | JS+CSS | 3h | ★★★☆☆ | 0* |
| 12 | 多跳证据图 | 第三批 | JS+SVG | 5h | ★★★☆☆ | 11 |
| 14 | Base UI 无头架构 | 第三批 | 全量重构 | 长期 | ☆ | — |

`0*` = 我插入的隐含任务，原 192 能力清单里没有，但不做它后面四项全废。

---

# 第一批（立即做，约 6 小时，今天能收工）

## [1] OKLCH Token 底座 — 纯 CSS

现状问题：只用了前景四级，剩下 201 个变量是死的。不要一次性写 201 行，**用 12 阶 ramp 生成器**，一个 hue 推导全部。

```css
:root {
  /* ── 主色种子：只需改这三个数，整站换肤 ── */
  --h: 155;          /* 森林绿 hue */
  --c: 0.16;         /* 主色 chroma */
  --h-accent: 158;   /* 翡翠绿 */

  /* ── 背景 ramp（12阶，Radix Scale 语义）── */
  --bg-1:  oklch(0.155 0.012 var(--h));  /* #0A100C 应用底 */
  --bg-2:  oklch(0.185 0.014 var(--h));  /* 卡片底 */
  --bg-3:  oklch(0.225 0.018 var(--h));  /* 悬浮元素 */
  --bg-4:  oklch(0.262 0.022 var(--h));  /* hover */
  --bg-5:  oklch(0.298 0.026 var(--h));  /* active */
  --bg-6:  oklch(0.345 0.030 var(--h));  /* 细分隔线 */
  --bg-7:  oklch(0.408 0.036 var(--h));  /* 边框 */
  --bg-8:  oklch(0.498 0.048 var(--h));  /* 强边框 / hover边框 */
  --bg-9:  oklch(0.740 var(--c) var(--h-accent)); /* 实心主色 #3BC77E */
  --bg-10: oklch(0.782 var(--c) var(--h-accent)); /* 主色 hover */
  --bg-11: oklch(0.800 0.120 var(--h-accent));    /* 低对比文字 */
  --bg-12: oklch(0.955 0.030 var(--h));           /* 高对比文字 */

  /* ── 前景四级（已有，改为派生）── */
  --fg-1: var(--bg-12);
  --fg-2: oklch(0.860 0.022 var(--h));
  --fg-3: oklch(0.700 0.020 var(--h));
  --fg-4: oklch(0.560 0.018 var(--h));

  /* ── Alpha 层：用 color-mix，不要手写 rgba ── */
  --a-2:  color-mix(in oklch, var(--bg-12) 4%,  transparent);
  --a-4:  color-mix(in oklch, var(--bg-12) 9%,  transparent);
  --a-6:  color-mix(in oklch, var(--bg-12) 16%, transparent);
  --a-9:  color-mix(in oklch, var(--bg-9)  22%, transparent);

  /* ── 语义色：同 ramp 结构，只换 hue ── */
  --danger:  oklch(0.66 0.20 27);
  --warn:    oklch(0.78 0.16 78);
  --info:    oklch(0.72 0.13 240);
  --success: var(--bg-9);

  /* ── glow 系统接入 OKLCH（替换现有硬编码）── */
  --glow-sm: 0 0 8px  color-mix(in oklch, var(--bg-9) 28%, transparent);
  --glow-md: 0 0 20px color-mix(in oklch, var(--bg-9) 34%, transparent);
  --glow-lg: 0 0 44px color-mix(in