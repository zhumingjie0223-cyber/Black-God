# TODO · 两仓合一：枢语 shuyu-lang 并入 Black-God

来源：权哥指示（2026-07-16）——"他们合并到一起！两个仓库"，以后只维护一个仓库。
方案：shuyu-lang 全部内容搬进本仓 `shuyu/` 目录；原 shuyu-lang 仓库封存为历史归档（不删）。

## 清单

- [x] 把 shuyu-lang 全部文件（除 .git）拷入 `shuyu/`
- [x] 修 `shuyu/` 内部跨仓路径：check-sync 自动比对上一级 `web/nexus-do/`；CLAUDE.md 措辞与命令改同仓相对
- [x] 修本仓侧引用：`tools/check-sync.mjs` 优先找本仓 `shuyu/`；根 CLAUDE.md、heavy-architect.md 更新说明
- [x] CI：shuyu 自带 ci.yml 迁入根 `.github/workflows/shuyu-ci.yml`（working-directory: shuyu + 路径过滤 + 同步校验 job）；移除 shuyu 内失效的嵌套 CI
- [x] 跑通验证：check-sync 双向引擎层完全同步；shuyu Node 27 过 / Python 9 过；神枢 build+selftest 108 过；sync-ui 双副本一致
- [ ] 提交推送本仓分支，开草稿 PR
- [ ] shuyu-lang 仓库：README 顶部加"已并入 Black-God"封存告示，推分支开草稿 PR
- [ ] 汇报权哥：合并完成后 shuyu-lang 可在 GitHub 设置里 Archive（只读封存）

## 总结

权哥名下只有 Black-God 和 shuyu-lang 两个仓库，要求并成一个。本次把枢语源头引擎
整个搬进 Black-God 的 `shuyu/` 子目录：一个仓库两块——`shuyu/` 是权威源头（Python+JS
双实现+词根表+测试），`web/nexus-do/` 是嵌入 Worker 的消费副本。同步校验从"跨仓传路径"
变成"同仓自动寻址"，两侧 check-sync.mjs 都能不带参数直接找到对方。枢语引擎测试迁进根 CI
（shuyu-ci.yml，按路径触发）。全部测试绿。关键：合并只动源码管理，**线上 App 零影响**
——神枢本体自带的引擎副本没动，build/selftest 全过。原 shuyu-lang 仓库加封存告示后，
由权哥在 GitHub 设置里 Archive（只读，不删，历史留存）。
