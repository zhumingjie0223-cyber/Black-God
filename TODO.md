# TODO · 按 Codex 主线完成 Black God iOS 1.2.0 正式上线与发布

开工：2026-09-09 08:27 (UTC+7)
基线：`codex/release-readiness` @ a862ddd（Codex 主线）
结果：代码侧已全部合入 `main`（e3568e8，标签 v1.2.0），GitHub 正式 Release「Black God 1.2.0 (8)」已发布；
Apple 上传与 App Store 审核提交属 Mac + 权哥本人（2FA）环节，见下方"剩余"。

## 步骤

- [x] 0. 核对 Codex 工作区现状（Mac 侧）：分支 / 365 行未提交 / 测试入口 / 证书 / Xcode 账号
- [x] 1. 365 行"自决策治理"代码 → 已在 Mac 侧提交为 51b0546（含旧治理文件兼容修复、UI 测试按需滚动修复），248 单元 + 13 UI 全过
- [x] 1b. UI 文案去 iSH，统一"内置执行环境"（Mac 侧随 51b0546 一并进 main；云端分支同样改动已被 main 覆盖）
- [x] 2. 构建号 1.2.0 (7) → (8)
- [x] 3. 云端可跑测试：枢语资源一致；JS 88 / Python 37 / 源码打包 5 全过
- [x] 4. Codemagic：评估后不改（Codex 主线 codemagic.yaml 已指向 BlackGod 工程；888 分支 preflight 不适用）
- [x] 5. 云端 PR #114：main 已先行合入同等内容，本分支已合回 main，现仅剩 TODO 归档差异，**不要当发布 PR 合并**
- [x] 6. 合并到 main + 打 tag v1.2.0（Mac 侧完成，e3568e8）
- [x] 7. GitHub Release v1.2.0「Black God 1.2.0 (8)」正式版（非预发布），源码包 + SHA-256 清单两个资产
- [x] 8a. 云端：为绕开 ASC 网页 502，接入并扩展 `ios-app/AppStore/asc.py`（基于 PR #112）：新增 status / select-build / review-info / age-rating / submit；19 项桩测试通过；补 1.2.0 更新说明（中英）、审核备注、年龄分级模板；SUBMIT_GUIDE 加"API 快速通道"
- [ ] 8b. 【Mac】归档 → App Store 导出 → 上传 1.2.0 (8) 到 App Store Connect
- [ ] 9a. 【权哥】生成 ASC API 密钥（App Manager）→ 放 Cursor Secrets；填 `metadata/age_rating.json`；网页完成 App 隐私问卷 / 截图 / 类别 / 定价
- [ ] 9b. 【云端】`asc.py check → push-metadata → select-build → review-info → age-rating → submit` 提交审核
- [ ] 10. 审核通过后：后台点「发布此版本」上架；把本文件归档到 docs/done/

## 剩余事项说明

- 第 8、9 步需要 Xcode 与 Apple 登录会话，只能在权哥 Mac 上的本地会话执行；云端 Linux 机器无法进行。
- 顺带发现：`.github/workflows/deploy-nexus.yml` 在每次 push main 时失败，原因是 `web/nexus-do/` 目录早在 7ed48e2（iOS 纯客户端重构）就已删除，
  工作流是僵尸配置，与本次发布无关；建议单独清理。

## 进度记录

- 08:28 Mac：`make test-ios` 252 单元通过，UI 4 项失败（旧脚本不滚动）
- 08:31 Mac：4 处 iSH 文案改品牌口径
- 08:36 云端接手：建分支 cursor/release-1-2-0-build8-1769，重做文案 + 构建号 + TODO 归档，开 PR #114
- 09:08 Mac 侧并行推进：51b0546 提交全部代码修复，09:16 合并 main、打 tag v1.2.0、发布 GitHub Release
- 11:4x 云端：确认 main 已包含一切，合并 main 回工作分支，PR #114 降为文档归档
