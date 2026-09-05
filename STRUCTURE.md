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
| `tools/push_to_github.sh` | 推送辅助脚本 |

> 原 `tools/check-sync.mjs` / `tools/sync-ui.mjs`（源头↔nexus-do 消费副本 / 主界面↔构建产物 双副本校验）
> 已随后端删除；双实现一致性现由 `shuyu/tests/engine.test.mjs` 的跨实现用例守护。

## 其它资产

| 路径 | 说明 |
|---|---|
| `web/`（静态资产） | 旧网页壳遗留的 `sw.js` / `manifest.json` / 图标 / `theme.css`；原由已删除的 nexus-do Worker 托管，现为孤立静态文件（取舍待权哥拍板，暂不动） |
| `android/` | Android TWA 上架材料 |
| `assets/` | 品牌资产（`logo/brand_logo.png` 神字 Logo 等） |
| `ui-spec/` | UI 设计规格 |
| `skills/` | 技能定义 |

## 文档（全部在 docs/ 下，入口 `docs/README.md`）

| 路径 | 说明 |
|---|---|
| `docs/plan/` | 规划与上线清单 |
| `docs/architecture/` `docs/spec/` | 架构与设计纲领 |
| `docs/product/` | 产品定位与对外材料（含 `ASI_GAP_AUDIT.md`） |
| `docs/done/` | 已完成任务归档（TODO/PROGRESS 完工后进这里） |
| `docs/archive/` | 历史归档（旧 Python server、收口下线页面、孤儿脚本等） |

## CI（`.github/workflows/`，共 2 条）

| 工作流 | 触发 | 作用 |
|---|---|---|
| `shuyu-ci.yml` | push/PR（`shuyu/**`） | 枢语 Node + Python 双实现测试 |
| `build.yml` | 手动 dispatch | iOS unsigned IPA 构建（macOS） |

> 已删除的僵尸工作流：`deploy-nexus.yml` / `nexus-do-ci.yml`（指向已删的 `web/nexus-do/`）、
> `exec-shell.yml`（神枢后端执行脑通道）。iOS 正式签名发布走仓库根 `codemagic.yaml`。
