# 神枢仓库结构

> 改动前先看这里。
> （2026-09-05 重写：iOS 转纯客户端后删除了 `web/nexus-do/` 后端，本文对照实际文件如实描述；
> 此前版本引用的 `web/nexus-do/nexus_do.core.mjs`、`tools/check-sync.mjs`、`worker.mjs`、`config/` 均已不存在。）

## 核心系统（两个 live 子系统）

| 路径 | 说明 |
|---|---|
| `ios-app/` | **iOS 原生 App（当前主体）**——纯客户端：用户自带 API Key 直连模型、本地存储、零后端；Agent 执行闭环（规划→执行→验证→重规划→交付）在此 |
| `ios-app/*.swift` | SwiftUI 界面 + `Nexus*` 运行时/工具/模型路由/记忆/验证等核心逻辑 |
| `ios-app/Theme.swift` | **设计令牌唯一权威源**（玄黑森林·翡翠活光） |
| `ios-app/project.yml` | xcodegen 工程定义（`xcodegen generate` 产出 `.xcodeproj`） |
| `ios-app/AppStore/` | App Store 上架材料（截图、中英文案、隐私政策、提交指南） |
| `shuyu/` | **枢语引擎权威源**（唯一源，无消费副本）：`shuyu_engine.py` ↔ `lexicon.js` 双实现 + 词根表 + `tests/` |

## 构建 / 测试

| 命令 | 说明 |
|---|---|
| `make test` | 枢语 Node + Python 全部测试（本机可跑） |
| `cd ios-app && xcodegen generate && open BlackGod888.xcodeproj` | 生成并打开 iOS 工程（需 macOS + Xcode） |
| `codemagic.yaml` | iOS 签名 + TestFlight 云端流水线 |

> 原 `tools/`（`check-sync.mjs` / `sync-ui.mjs` / `push_to_github.sh`）已整体移除或归档：前两者是 nexus-do 消费副本校验，
> 随后端删除；后者硬编码旧服务器路径且 `git add .` 一把梭，归档进 `docs/archive/nexus-do后端时代-2026-09-05/tools/`。
> 双实现一致性现由 `shuyu/tests/engine.test.mjs` 的跨实现用例守护。

## 其它资产

| 路径 | 说明 |
|---|---|
| `assets/logo/brand_logo.png` | 品牌 Logo（与 `ios-app/AppIcon.png` 同一张图）；`assets/` 下现在只有这一个文件 |

> 2026-09-05 已归档进 `docs/archive/nexus-do后端时代-2026-09-05/`（零引用）：`web/`（旧 PWA 静态壳，调用已删的 `/api/push/*`）、
> `skills/`（依赖不存在的服务器路径、含红队内容）、`ui-spec/`（旧人物化 UI 方案）、`android/`（TWA 材料，指向已删网页版域名）、
> `assets/sihan/`（旧人物「思涵」素材，品牌已去人物化）。

## 文档（全部在 docs/ 下，唯一索引 `docs/README.md`）

| 路径 | 说明 |
|---|---|
| `docs/product/` | 现行：`BLACK_GOD_NEXUS_CANONICAL.md`（产品唯一真相）、`ASI_GAP_AUDIT.md`、项目介绍等 |
| `docs/spec/` | 现行：核心哲学、设计纲领 |
| `docs/architecture/` `docs/design/` `docs/api/` | 通用参考（Agent 内核理论、自主意识方案、API 镜像；`DESIGN_SYSTEM_V3.md` 是未采用的备选方向） |
| `docs/done/` | 已完成任务归档（TODO/PROGRESS 完工后进这里） |
| `docs/archive/` | 历史归档；`nexus-do后端时代-2026-09-05/` 下是后端删除时整体搬入的旧计划/架构/部署/上架文档与遗留目录 |

## CI（`.github/workflows/`，共 2 条）

| 工作流 | 触发 | 作用 |
|---|---|---|
| `shuyu-ci.yml` | push/PR（`shuyu/**`） | 枢语 Node + Python 双实现测试 |
| `build.yml` | 手动 dispatch | iOS unsigned IPA 构建（macOS） |

> 已删除的僵尸工作流：`deploy-nexus.yml` / `nexus-do-ci.yml`（指向已删的 `web/nexus-do/`）、
> `exec-shell.yml`（神枢后端执行脑通道）。iOS 正式签名发布走仓库根 `codemagic.yaml`。
