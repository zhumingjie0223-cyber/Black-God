# TODO — 回溯式复盘审计(权哥 2026-07-17 指令:用回溯技能查项目+纠正)

铁律:先懂再动 · 不许假(每条自己真跑验过) · 只增不删 · 力量沉里子。
方法:回头把"声称完成"的逐条真跑核对,查出偏差当场纠正。

## 步骤

- [x] 1. 构建+自测:409027 字节 · selftest 108 过 0 挂 ✓
- [x] 2. 引擎双副本同步:check-sync 引擎层完全同步 ✓(数据层 3 处产品定制分叉,允许)
- [x] 3. UI 双副本同步:主界面+工作台双副本一致 ✓
- [x] 4. 枢语源头引擎测试:Node 27 过 0 挂 ✓
- [x] 5. 枢语 Python 测试:9 过 ✓
- [x] 7. shuyu-lang 封存告示已到位 ✓(独立仓 README 顶部有并入告示)
- [x] 8. 逮到偏差:陈旧容量 29.5亿(实测 76.7亿=7,667,712,000)散落 6 处活文件
      → 已纠正:shuyu/README.md×3、根 README×2、nexus_do.core.mjs 注释×1
      → 重新构建同步 nexus_do.mjs + 复验全套
- [x] 6. 核对旧 PR + 铁律引用:
      · shuyu-lang 仓已封存 → #3/#6 应关(仓库只读,PR 无处可合)
      · #27 隐私页已由 #37 进主线;#30 的 tools(check-sync/sync-ui)已在主线
      · ⚠ 决策点1:CLAUDE.md 设计系统铁律引用 web/design/tokens.css + docs/design/DESIGN_SYSTEM_V3.md
        —— 这俩文件主线不存在(只在未合的 PR #29 分支)。index.html 是内联 CSS 变量,线上无死链。
        需权哥拍板:合 #29 让铁律成真,还是改铁律措辞
      · ✓ /api/confirm 红线仍在 web/index.html(老首页);nexus-do 用"系统专属"能力门禁,未移除
- [x] 9. 中文提交推送 designated 分支,开草稿 PR
- [ ] 10. TODO.md 写总结,归档 docs/done/

## 红线
- 不动神枢核心设定/人格/原点;不删不覆盖任何现有词根/测试
- `/api/confirm` 二次确认红线不得移除
- 先备份再删除,禁止 rm -rf / git add -A 一把梭
