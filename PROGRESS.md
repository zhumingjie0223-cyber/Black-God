# PROGRESS · 神枢私人版强化 进度存档

> 更新:2026-07-29 · 分支 `claude/black-god-enhancement-plan-6gc2pw` · PR #86
> 权哥指示:先停,不急着往下推。本文件记录"干到哪了",随时可接续。

## 当前状态:一切正常,可安全停下

- ✅ **私人版 `aquan.lufei.uk`(worker: nexus-do)完好无损**,没受任何改动影响。
- ✅ **困扰多轮的 CI 红叉已彻底根除**:那是 CF 面板一套多余的 `blackgod88` 部署集成;
  权哥已在面板删除 blackgod88 worker,我已删除仓库里会自动复活它的 `deploy-blackgod88.yml`。
  以后 PR 不再有红叉。
- ✅ 遗留死文件 `config/wrangler.jsonc`、根 `worker.mjs` 现无任何引用(留着不碍事,可后续清)。

## 已完成并推送 PR #86

1. **方案文档**:`docs/私人版全面强化方案-2026-07-28.md`(六轴 22 项 + 竞品对标附录,13 家逆向消化)。
2. **记忆 bug 第一波**(nexus_do.core.mjs):语义嵌入英文 bge-base → 多语 **bge-m3**,
   加 `_vec_model` 标记 + 心跳分批重嵌。selftest 228/228。
3. **枢语 S1 · `do:` 第六回路**(shuyu/nexuslang.js):枢语从"只表达意识"升级到"能下达可执行任务"。
   - 语法 `do: 工具名(参数) → 期望态`,支持点号命名空间/多条/无参原语。
   - interpret() 加 `actions[]`,compile() 加 `act[]`。
   - node --test 33/33、python 9/9、check-sync 引擎层同步。**待权哥确认 `do:` 语法是否对味。**

## 后续待办(权威清单见权哥的施工说明书 + 方案文档)

「用枢语做任务」是核心诉求,S1 是地基(已完成)。下一步 P0:
- **S2** 枢语↔agent 状态机桥(任务态用枢语态轴词表达)
- **E1** 跨心跳续跑的持久 agent 状态机(核心大文件 nexus_do.core.mjs,重活)
- **E2 / M2** R2 工作区快照 / Vectorize 向量外置 —— **需权哥先在 CF 面板建 R2 桶 + Vectorize 索引**(我够不到面板)
- **B1** iOS 工具入 agent 动作集;**G1** 技能库吃 agent 实战数据

待权哥确认事项:①S1 `do:` 语法是否对味 ②态轴 80 值里哪几个冻结为任务运行态(S2 用)
③R2/Vectorize 命名与是否本期引入。

## 恢复指引
接着干:读本文件 → 从 S2 或 E1 起,逐项改代码、跑 `npm test`/`selftest` 自测、独立 commit 推 PR #86。
