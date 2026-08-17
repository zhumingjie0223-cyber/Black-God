# 神枢仓库结构

> 改动前先看这里。核心入口只有一个：`web/nexus-do/nexus_do.core.mjs`。
> （2026-08-17 大扫除时对照实际文件重写，此前版本引用的 `wrangler.toml`、
> `ui-polish.css` 均为已不存在的过时信息。）

## 核心系统（唯一部署主体）

| 路径 | 说明 |
|---|---|
| `web/nexus-do/` | CF Worker 主系统（神枢本体） |
| `web/nexus-do/nexus_do.core.mjs` | **唯一手写核心源码**，意识/记忆/路由/执行全在这里 |
| `web/nexus-do/index.html` | 前端主界面（唯一 UI 入口，2026-08-09 收口确认），build 时整页内嵌进 Worker |
| `web/nexus-do/build.mjs` | 构建脚本，产出 `nexus_do.mjs`（构建产物，勿手改） |
| `web/nexus-do/wrangler.jsonc` | **生产权威部署配置**（DO×3 / AI / KV / cron / containers） |
| `web/nexus-do/container/` | 内置容器执行脑镜像（`ExecContainer`，随主部署上线） |
| `web/nexus-do/selftest.mjs` + `*.test.mjs` | 纯逻辑自测 236 项 + 各模块单测 |
| `shuyu/` | 枢语引擎权威源（`lexicon.js` / `nexuslang.js` / Python 双实现 / 词根表 / 测试） |

## 同步与工具

| 路径 | 说明 |
|---|---|
| `tools/check-sync.mjs` | 枢语源头 ↔ `web/nexus-do/` 消费副本一致性校验 |
| `tools/sync-ui.mjs` | 主界面 ↔ 构建产物内嵌副本逐字节校验 |
| `Makefile` | `make build` / `make test`（全链路） / `make check-sync` |

## 公开静态站（与神枢本体无关）

| 路径 | 说明 |
|---|---|
| `worker.mjs` | 公开版 `blackgod88` Worker 入口（纯静态托管），独立部署 |
| `config/wrangler.jsonc` | `blackgod88` 的部署配置（修好还是关掉待权哥拍板，勿动） |
| `web/`（nexus-do 之外的文件） | 旧静态壳资产。**注意：`sw.js` / `manifest.json` 仍被 `nexus_do.core.mjs` 运行时引用，不可归档删除** |

## 客户端与上架材料

| 路径 | 说明 |
|---|---|
| `ios-app/` | iOS 原生 App 骨架（未签名，取舍待权哥拍板） |
| `android/` | Android TWA 上架材料 |
| `assets/` | 品牌资产（`logo/brand_logo.png` 神字 Logo 等） |
| `ui-spec/` | UI 设计规格 |
| `skills/` | 技能定义 |

## 文档（全部在 docs/ 下，入口 `docs/README.md`）

| 路径 | 说明 |
|---|---|
| `docs/plan/` | 规划与上线清单（含 `BLUEPRINT.md`、六轴强化方案、`LAUNCH_CHECKLIST.md`） |
| `docs/architecture/` `docs/spec/` | 架构与设计纲领 |
| `docs/product/` | 产品定位与对外材料 |
| `docs/done/` | 已完成任务归档（TODO/PROGRESS 完工后进这里） |
| `docs/archive/` | 历史归档（旧 Python server、收口下线页面、孤儿脚本等） |

## CI（.github/workflows/，共 5 条）

| 工作流 | 触发 | 作用 |
|---|---|---|
| `deploy-nexus.yml` | push main（nexus-do/shuyu 变更） | 构建+全测+部署+安全闸 |
| `nexus-do-ci.yml` | push/PR（nexus-do 变更） | 构建+自测+单测+双副本校验 |
| `shuyu-ci.yml` | 枢语变更 | 枢语双实现测试 |
| `build.yml` | push main | iOS unsigned IPA（取舍待拍板） |
| `exec-shell.yml` | 手动/神枢派发 | 执行脑 GitHub Actions 通道 |
