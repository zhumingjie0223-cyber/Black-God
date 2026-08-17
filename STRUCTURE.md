# 神枢仓库结构

> 改动前先看这里。核心入口只有一个：`web/nexus-do/nexus_do.core.mjs`。

## 核心系统

| 路径 | 说明 |
|---|---|
| `web/nexus-do/` | CF Worker 主系统（私人版 `aquan.lufei.uk`） |
| `web/nexus-do/nexus_do.core.mjs` | **唯一手写源码**，所有功能在这里 |
| `web/nexus-do/build.mjs` | 构建脚本，产出 `nexus_do.mjs`（勿手改产物） |
| `web/nexus-do/wrangler.toml` | CF 部署配置，`main = nexus_do.mjs` |
| `web/nexus-do/index.html` | 前端主界面，build 时内嵌进 core |
| `web/nexus-do/ui-polish.css` | UI 优化层，build 时注入 body 末尾 |
| `shuyu/` | 枢语引擎（`lexicon.js` / `nexuslang.js` / `lexicon_data.js`） |
| `worker.mjs` | 公开版 blackgod88 Worker，独立部署，与 nexus-do 无关 |

## iOS 客户端

| 路径 | 说明 |
|---|---|
| `ios-app/` | iOS Swift 客户端（BlackGod.xcodeproj） |

## 支撑工具

| 路径 | 说明 |
|---|---|
| `tools/sync-ui.mjs` | UI 双副本同步校验工具 |
| `tools/check-sync.mjs` | 枢语引擎同步校验 |
| `skills/` | 神枢技能库 |
| `.github/workflows/nexus-do-ci.yml` | CI：228项selftest + 同步校验 |
| `.github/workflows/deploy-nexus.yml` | CD：部署到 CF Worker |

## 文档

| 路径 | 说明 |
|---|---|
| `docs/architecture/` | 架构设计文档 |
| `docs/spec/` | 规格与哲学文档 |
| `docs/plan/` | 施工计划 |
| `docs/done/` | 近期完成任务记录 |
| `docs/archive/` | 归档（redteam / server / nexus-studio / done / claude-agents） |

## 归档说明

`docs/archive/` 下的内容仅存档，不参与构建和部署：
- `server/` — Python 本地测试壳（历史遗留）
- `redteam/` — 52pojie 原始素材
- `nexus-studio/` — Studio UI 历史版本
- `done/` — 已完成任务记录（2026-07-*）
- `claude-agents/` — Claude Code 会话配置
