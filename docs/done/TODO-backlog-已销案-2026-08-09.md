# 代码遗留待办 Backlog

> 收官整理(2026-08-03)扫描 `web/nexus-do` 全部 `.mjs`/`.js` 后记录的**不确定项**。
> 原则:确定的 bug 当场修;拿不准、涉及行为改动或部署红线的,只记录不擅动(见根 `CLAUDE.md` 铁律)。
> 本次扫描**未发现确定 bug**,以下均为待权哥定夺的观察项。
>
> **✅ 本账本已于 2026-08-09 全部销案清零(权哥拍板「直接收口」)**,三条处置结果见各节标注。
> 新的遗留项另起新账,不要续写本文件。

## 1. 空 catch 吞异常(9 处,均为"尽力而为"式,暂判非 bug) —— ✅ 已销案(2026-08-09)

权哥拍板直接收口:9 处均为刻意的"尽力而为"式吞异常,判非 bug,**维持现状销案**。
日后排障若需留痕再单独立项。以下为原始记录:

这些 catch 故意吞掉异常以免非关键路径失败拖垮主流程,**属既有风格,非明确 bug**,不擅改。
若日后排障需要,可考虑加一行 `console.debug` 留痕(不改变控制流)。

| 文件:行 | 场景 | 判断 |
|---|---|---|
| `nexus_self_improve.mjs:17` | 派发 CustomEvent 失败 | 事件总线可选,尽力而为,保留 |
| `nexus_self_improve.mjs:41` | 写记忆失败 | 记忆可选,保留 |
| `verdict_source.mjs:140/146/152` | 多源取证解析失败 | 单源失败不应中断整体裁决,保留 |
| `container/task_runner.mjs:53/284` | 容器任务清理/解析 | 清理路径,吞异常合理,保留 |
| `reverse_kb.mjs:154/705` | **代码生成模板字符串内**的 Frida hook 片段 | 是生成物,不是运行时逻辑,正确无误 |

## 2. wrangler 双配置文件并存 —— ✅ 已销案(2026-08-09 权哥拍板执行)

核实 CI 全部工作流无一引用 `wrangler.toml` 后,已归档删除(备份 `docs/archive/wrangler.toml.2026-08-09.bak`)。
以下为原始记录:

`web/nexus-do/` 同时存在:
- `wrangler.toml` —— 旧,`compatibility_date = 2025-01-01`,只有 `SHENSHU` 一个 DO 绑定,**缺** `AGENT_STATE_MACHINE`/`EXEC_CONTAINER` 绑定、缺 `migrations`、缺 `containers`、缺 `account_id`。
- `wrangler.jsonc` —— 生产权威版,`compatibility_date = 2026-06-29`,含 `account_id`、三个 DO 绑定、`migrations`、`containers`、cron 触发器等完整配置。

**问题**:wrangler 同目录存在多份配置会有优先级歧义,`wrangler.toml` 明显是被 `wrangler.jsonc` 取代的过期副本。
**建议**:归档删除 `wrangler.toml`(先移进 `docs/archive/` 再删)。
**为何本次没删**:涉及部署配置(CLAUDE.md 铁律:不碰服务器/部署除非权哥明确要求;删前必先备份核实)。需权哥确认 CI 是否显式引用 `wrangler.toml` 后再动。

## 3. container/package.json 用 `playwright-core: "latest"` —— ✅ 已销案(2026-08-09 权哥拍板锁定稳定版)

已锁定为 `"playwright-core": "1.62.1"`(执行日 npm 仓库最新稳定版),容器镜像自此可复现。以下为原始记录:

`web/nexus-do/container/package.json` 依赖 `"playwright-core": "latest"`。
`latest` 会随构建时间漂移,可能引入不可复现的镜像。**建议**锁到具体版本号(如 `"1.xx.x"`)以保证容器镜像可复现。非当前 bug,待权哥决定锁哪个版本。
