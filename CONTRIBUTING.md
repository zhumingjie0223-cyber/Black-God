# 贡献指南

本仓库有两个 live 子系统，改动前先看 `STRUCTURE.md`：

| 子系统 | 路径 | 本地怎么跑 |
|---|---|---|
| iOS App（纯客户端） | `ios-app/` | 需 macOS + Xcode：`cd ios-app && xcodegen generate && open BlackGod888.xcodeproj` |
| 枢语引擎（Python + JS 双实现） | `shuyu/` | 任何机器：仓库根 `make test`（= Node 84 项 + Python 33 项） |

## 流程

1. 从 `main` 切分支，命名 `feature/xxx` / `fix/xxx` / `docs/xxx`。
2. 多步骤任务先在仓库根写 `TODO.md` 拆步骤，完工后归档到 `docs/done/`（见 `CLAUDE.md` 铁律）。
3. 提交信息、PR 标题与描述**一律中文**。
4. 只 `git add` 你改的文件，不要 `git add -A` / `git add .` 一把梭。
5. 提 PR，按模板填。

## 各子系统规则

**iOS**
- 设计令牌只改 `ios-app/Theme.swift`，不在视图里硬编码颜色。
- 危险操作审批闸（`NexusPermissionGate` / `NexusApprovalQueue`）不得绕过或移除。
- 工程由 `project.yml` 生成，不要提交 `.xcodeproj` / `Info.plist`。
- 上架材料与自动化在 `ios-app/AppStore/`（`SUBMIT_GUIDE.md`、`asc.py`）。

**枢语**
- 词根表只能在轴尾追加，绝不改动/删除/重排已有词根。
- 改引擎必改双侧（Python + JS），`make test` 全绿再提。
- 详见 `shuyu/CLAUDE.md`。

## 文档

- 现行文档放 `docs/` 对应子目录，索引见 `docs/README.md`；历史材料进 `docs/archive/`，不改写历史。
- 涉及已删除的 Cloudflare 后端（`web/nexus-do/`）的内容一律标为历史，不要以现在时态描述。

## 问题反馈

用仓库 Issues，按模板填。

## 许可证

MIT，见 `LICENSE`。
