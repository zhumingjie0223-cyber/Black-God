# Black God 主升级规划

> opus5统筹 · 2026-07-26

# 一、升级规划

## 前端（3 批）

| 批次 | 能力名 | 实现方式 | 代码量 | 优先级理由 |
|---|---|---|---|---|
| **B1** | OKLCH 12 阶 color ramp | 补全 `:root` 变量，双锚点固定 `#0A100C`(step1) / `#3BC77E`(step9)，中间按感知均匀插值；`@supports` 提供 hex 回退 | ~90 行 CSS | 所有后续 UI（Diff/CoT/调色板）都依赖色阶，不先补齐后面全是硬编码 |
| **B1** | 流式打字机 | `StreamTypewriter` 类，RAF 驱动 + 自适应吐字速率 + 缓冲队列 + 光标 DOM | ~180 行 JS | 流式是 LLM 产品的第一感知，投入产出比最高 |
| **B2** | BlockRenderer 消息块协议 | 消息体从 string 改为 `Block[]`，注册表 `{type: renderer}`，text/code/diff/cot/artifact/tool | ~260 行 | 所有富内容的地基，必须先于 CoT/Diff |
| **B2** | 思维链 CoT 折叠 | `<details>` 语义化 + 高度动画 + 流式期间自动展开、完成后自动收起 | ~110 行 | 依赖 BlockRenderer；直接提升"可信度"观感 |
| **B2** | Diff 块渲染 | unified diff 解析 → hunk 分组 → 行级 add/del/ctx 着色（用 ramp step 6/9） | ~150 行 | 依赖 BlockRenderer + 色阶 |
| **B2** | 流式 Artifact 消费 | 增量解析 `<Artifact><File path>`，边流边建文件树 tab | ~170 行 | 与后端 B3 对接，前端先就绪 |
| **B3** | 9 套调色板热切换 | 只改 `--h`/`--c-scale` 两个变量 + `localStorage`，ramp 自动重算 | ~70 行 | ramp 建好后成本极低，纯增值 |
| **B3** | Web Vitals RUM | `PerformanceObserver` 采 LCP/INP/CLS/TTFB，`sendBeacon` 上报 | ~90 行 | 非阻塞，可观测性补齐 |
| **B3** | History API SPA 追踪 | monkey-patch `pushState/replaceState` + `popstate` | ~50 行 | 依赖 RUM 管道 |
| **B3** | flock.js 敏感字段脱敏 | 上报前递归遍历，key 正则 + 值正则双匹配打码 | ~80 行 | 合规兜底，必须在 RUM 之后 |
| **B3** | 反爬熔断过滤 | UA/无头指纹/频