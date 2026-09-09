# TODO · 按 Codex 主线完成 Black God iOS 1.2.0 正式上线与发布

开工：2026-09-09 08:27 (UTC+7)，08:36 后执行环境从权哥的 Mac 切到云端 Linux 机器
基线：`codex/release-readiness` @ a862ddd（Codex 主线，已推送）
工作分支：`cursor/release-1-2-0-build8-1769`

## 环境切换说明（重要）

Mac 上那份 Codex 工作区（`~/Documents/Codex/2026-09-08/ke/work/Black-God`）里有 **365 行未提交的"自决策治理"代码**
和我 08:31 改的 4 处去 iSH 文案，**都只在 Mac 本地，云端拿不到**。云端只能做不依赖 Xcode 的事；
打包 / 上传 Apple / 提审 必须回 Mac 或走 Codemagic CI。

## 步骤

- [x] 0. 核对 Codex 工作区现状（Mac 侧完成）：分支/未提交改动/测试入口/证书/账号均已确认
- [x] 1b. UI 文案去 "iSH"（Mac 侧已改但未提交；云端重新应用一遍到工作分支）
- [~] 1c. 首轮全量测试（Mac 侧）：252 单元测试全过；UI 13 项 9 过 4 败，重跑被环境切换打断
- [x] 2. 云端：`ios-app/project.yml` CURRENT_PROJECT_VERSION 7 → 8
- [x] 3. 云端测试：枢语资源与权威源一致；JS 88 项通过；Python 37 项通过；源码打包工具 5 项通过
- [x] 4. Codemagic：评估后**不改**——Codex 主线的 codemagic.yaml 已指向 BlackGod 工程；888 分支的 preflight.mjs 绑定该分支结构（本地化 URL 文件、共享检查等），套过来 8 项误报，不值得为它改仓结构
- [ ] 5. 云端：提交、推送、开 PR（目标 main）；Codex 原 TODO.md（145 行）已归档到 docs/done/
- [ ] 6. 【需回 Mac】提交那 365 行代码并推送；归档 → 导出 → 上传 1.2.0 (8)
- [ ] 7. 【需权哥】App Store Connect 填版本信息 / 隐私标签 / 分级 / 选构建 → 提交审核（2FA 只能人做）
- [ ] 8. GitHub Release v1.2.0-build8 正式版；合并 PR 到 main 并打 tag
- [ ] 9. 写总结，TODO.md 归档到 docs/done/

## 进度记录

- 08:28 Mac：`make test-ios` 252 单元测试通过，UI 4 项失败（历史日志显示本就不稳定）
- 08:31 Mac：4 处 iSH 文案改为品牌口径（未提交，留在 Mac）
- 08:38 云端：从 origin/codex/release-readiness 建分支 cursor/release-1-2-0-build8-1769
