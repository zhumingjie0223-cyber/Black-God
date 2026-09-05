# TODO — 仓库收口：清死文档 / 修僵尸 CI（nexus-do 后端已删）

> 背景：2026-09-05 iOS 转纯客户端时删掉了 `web/nexus-do/` 后端，但一批 live 文档/CI/工具仍把它当唯一部署主体。
> 分支 `cursor/repo-docs-hygiene-96d7`（off main）。只动 live/权威文件与 CI，历史记录(CHANGELOG/docs/plan/docs/design/shuyu/TODO)不动。

## A. 修/删僵尸 CI（有两个活 bug：改 shuyu 会触发失败）
- [ ] A1. 删 `deploy-nexus.yml`（触发于 shuyu/**，job `cd web/nexus-do` 必失败；且无 worker 可部署）
- [ ] A2. 删 `nexus-do-ci.yml`（只触发于已删的 web/nexus-do/**，永不运行）
- [ ] A3. 删 `exec-shell.yml`（神枢执行脑通道，dispatcher 随后端删除；顺带收掉任意命令执行面）— PR 里点名待权哥可否
- [ ] A4. 修 `shuyu-ci.yml`：去掉 web/nexus-do 触发路径；删会崩的 `sync-check` 作业

## B. 删过时工具 + 清引用
- [ ] B1. 删 `tools/check-sync.mjs` `tools/sync-ui.mjs`（仅服务已删的 nexus-do 消费副本；check-sync 现直接崩）
- [ ] B2. `shuyu/package.json` 去 `check-sync` 脚本
- [ ] B3. `Makefile` 重写为 shuyu-only（build/test），去 sync-ui/check-sync，注明 iOS 走 Xcode/CI

## C. 改 live 权威文档为现状（iOS 客户端 + shuyu 引擎；nexus-do 已删可从 git 找回）
- [ ] C1. `CLAUDE.md`（根）：两仓合一段、常用命令、设计系统铁律(index.html 已不存在)、改 index.html 铁律
- [ ] C2. `STRUCTURE.md`：核心入口、工具、CI 表
- [ ] C3. `README.md`：badge、目录结构、部署段
- [ ] C4. `shuyu/CLAUDE.md` + `shuyu/README.md`：去「消费副本 web/nexus-do」表述，shuyu 现为唯一源

## D. 验证 + 提交
- [ ] D1. 跑 shuyu 测试（Node + Python）确认 CI 依赖的命令仍绿
- [ ] D2. 逐项提交 + 推送 + 建 PR（draft），归档 TODO 到 docs/done/

## 结论
（完工后补）
