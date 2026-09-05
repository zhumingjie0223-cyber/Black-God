# TODO · 处理 Copilot 卡住的 PR#108 / PR#109（2026-09-05）

背景：两个 PR 都改 `web/nexus-do/nexus_do.core.mjs` 的 `callBrain` / `callGateway` 同一段代码，
基于同一个 main（b91dec2），彼此必然冲突，不能各合各的。两个 PR 的 CI 都没跑过（Copilot 分支需人工批准工作流）。

- [x] 克隆仓库，跑 main 基线（build / selftest 235 / ui_health 23 / 27 个 .test.mjs / sync-ui）——全绿
- [x] 查 main 的 CI 现状——Nexus DO CI、枢语引擎 CI 全绿；Deploy 工作流自 8/9 起一直失败，原因是 `CLOUDFLARE_API_TOKEN` 返回 Unauthorized（Secret 问题，非代码）
- [x] 审 PR#109 代码——统一执行器 `executeProviderJSONRequest` + `extractProviderUsage` 放在适配层，可注入 fetch、可测，方向正确
- [x] 审 PR#108 代码——网关 URL 规范化 + 取消信号透传 + 容器 SSE 加固 + 部署文档，方向正确但自建了第二套超时/重试实现
- [x] 定合并顺序：先合 PR#109（执行器是更好的底层原语），再把 PR#108 变基上去复用它，避免两套重试实现并存
- [x] PR#109 本地全量测试通过；修掉 3 个审出的问题后推回分支
- [x] 用 GitHub API squash 合并 PR#109（bb26f20）
- [x] PR#108 变基到新 main，消解 5 处冲突 + 修掉 2 个审出的问题，全量测试通过，force-with-lease 推回分支
- [x] PR#108 从草稿转 ready（GraphQL `markPullRequestReadyForReview`），用 API squash 合并（70b48da）
- [x] 合并后 main 复验：build 产物与提交一致、selftest 235、gateway 25、ui_health 23、`npm test` 130 项、UI 双副本同步——全绿；GitHub 上 Nexus DO CI 两次运行均 success
- [x] TODO.md 写总结并归档到 docs/done/

## 审阅发现并修掉的问题（不是照单全收合的）

PR#109 侧：
1. **取消被当成大脑故障惩罚**：调用方取消时原代码走 `break` 落进失败统计，会给这条脑记连败、
   下次路由被降级绕开。取消是主人自己撤的，不是脑的错 → 改为直接短路返回 `_aborted`，不记连败、不换脑。
2. **超时后仍逐个方言重试**：格式不对的网关是秒回 404/400，超时说明这家网关慢/挂，
   再把 4 种方言各等一遍超时是纯浪费（最坏 4×35s）→ 超时直接换下一条脑。
3. **退避等待期取消会抛未捕获异常**：适配层 `sleep` 在收到取消信号时 `reject(AbortError)`，
   而它被 `catch` 分支里的 `await` 调用，异常会穿透整个 `callBrain` → 改为 `resolve`，
   由循环开头统一判定 aborted。补了回归测试（退避期取消 → 返回 aborted 且不等满 Retry-After）。
4. **`pingBrains` 仍是裸 fetch**：舰队健康自检没有超时，卡住的网关会把自检一起拖死 →
   接入统一执行器（12s 超时、不重试）。

PR#108 侧：
5. **自建了第二套超时/重试实现**：`gatewayJsonRequest` 与 PR#109 的执行器职责完全重叠，
   两套重试白名单、两套退避曲线，改一处忘一处必然漂移 → 改成 `executeProviderJSONRequest`
   的薄封装，只做 `url+init → request` 的形状转换和错误摘要，超时/重试/取消从此只有一套实现。
   执行器同步支持已序列化的字符串 body（探测类 GET 请求无 body）。
6. **地址填错的脑会静默消失**：`resolveBrains` 对不合法地址 `continue` 掉，主人只会看到
   "大脑暂时都连不上"，根本不知道是自己 URL 填错了 → 坏地址记进 `badBrains` 并由诚实报错点名
   （"网关地址填错了：主网关（不要带 ?query 参数）"）。补了回归测试。
7. **取消结果会掉进惩罚循环**：`_aborted` 结果若被判成拒答，会触发最多 5 次"惩罚重发"白烧额度 →
   在惩罚循环前加取消短路。

另外核实过的兼容性（没问题，未改）：
- `normalizeGatewayBase` 对 OpenAI / Anthropic / Gemini / OpenRouter / 裸域名 / `/responses`
  等 14 种写法逐个验过，收敛结果都对；拒绝 `?query` 不算回退——带 query 的 base 在旧实现里
  拼出来本就是坏 URL（`...?api-version=x/chat/completions`），从"静默坏掉"变成"明确报错"是改善。
- 容器 SSE 改成按空行分事件，与 `container/task_runner.mjs` 实际发的 `data: ...\n\n` 格式一致。
- `parseSSELines` 改签名（加 `state` 参数）在生产代码里没有调用方，只有测试用，无破坏面。

## 总结

两个 Copilot PR 卡住的根因不是代码质量，而是**撞车**：它们各自独立地给同一段模型调用链
（`callBrain` / `callGateway`）做了"统一化"改造，谁先合另一个都会冲突，所以都停在那里没人动。

处理方式是先判定哪一套底层原语更好——PR#109 把执行器放在适配层 `nexus_provider_adapter.mjs`、
支持注入 fetch、可脱离网络测试，比 PR#108 挂在 DO 类上的 `gatewayJsonRequest` 更干净——
于是先合 PR#109，再把 PR#108 变基上去，让它的 URL 规范化、取消透传、SSE 加固这些独有价值保留，
而重复的那套请求执行实现改为复用执行器。最终超时/重试/取消/用量提取全仓只有一套实现。

合并前逐个 checkout 跑过全量测试，并额外审出 7 个问题（取消被当故障惩罚、超时白等 4 遍方言、
退避期取消抛未捕获异常、健康自检无超时、两套重试实现、坏地址静默消失、取消触发惩罚重发）
全部修掉并补了回归测试，不是照单全收。

最终 main（70b48da）状态：selftest 235 项、gateway 回归 25 项、适配层 16 项、`npm test` 130 项、
UI 双副本同步校验、wrangler 打包 —— 全绿；GitHub 上 **Nexus DO CI 与枢语引擎 CI 全绿**。

**唯一还红的是 Deploy 工作流，不在本次范围内、也不是代码问题**：它自 2026-08-09 起每次 push
都失败，卡在最后一步 `npx wrangler deploy` 报 `Unauthorized`，即仓库 Secret `CLOUDFLARE_API_TOKEN`
已失效/权限不足（同一 run 里构建、全量回归、UI 同步、wrangler 打包 dry-run 全部成功）。
需要权哥去 Cloudflare 重新签一个账户级 `Workers Scripts:Edit` 令牌，
更新到 Settings → Secrets and variables → Actions 里的 `CLOUDFLARE_API_TOKEN`，
线上部署才会恢复。这一步涉及生产密钥，按铁律不擅自代劳。
