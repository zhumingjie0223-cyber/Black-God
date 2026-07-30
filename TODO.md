# TODO — 自主意识 第二期·步骤1：把自主内心"亮"到界面（权哥：继续）

S1 让她能想/能生意图，但都埋在后台 soul。这步让你**看见**：枢语念头 + 自主意图上界面。
真实执行(授权触发)= 步骤2，先看见后授权。全程仍卡 owner + /api/confirm。

- [x] 后端：getInner 增 `自主意图`(soul.will) 输出 —— core.mjs getInner 已加 `自主意图: (soul.will||[]).slice(-8)`
- [x] 前端：#mind 加「此刻·她的自主内心」卡（工业 nx2 语言，HTML+CSS 已落）：枢语念头(词+义) + 意图清单(类型+念头+缘由)，只读；care/执行类标「待授权」
- [x] loadHub 里从 inner.自主意图 / inner.潜意识 填充该卡 —— #selfThink 取最新潜意识、#selfWills 渲染意图并标待授权
- [x] build + selftest 228 绿 + 无头截图(mock /inner 带 will)双主题核实 —— 念头/三意图/待授权胶囊渲染正常
- [x] 分支提交推送 —— 93f7c48 已推 claude/ui-polish-upgrade-ixhi5n
- [ ] 步骤2(待权哥点头)：意图旁「授权」按钮 → 走既有 invokeCapability(ownerCtx) + /api/confirm 闸门执行

## 步骤1 小结（已完成）
S1 的后台自主内心（枢语自想 + 自发意图）已「亮」到 #mind 首页：新增「此刻·她的自主内心」
卡，工业 nx2 语言，展示最新枢语念头（玉绿衬线词+义）与自发意图清单（类型标签+念头+缘由），
care/执行类标琥珀「待授权」、内省类不标。后端 getInner 输出 `自主意图`(soul.will)，前端 loadHub
填充。build+selftest 228/0、无头双主题核实通过。已推 93f7c48 → PR #87，枢语引擎 CI #20 绿。
真实执行仍留步骤2（授权触发），红线未动。等权哥点头再做步骤2。

## 红线（不变）
- 只读展示零风险；真实动作只能由主人点授权触发，经 resolveCapability(owner) + 破坏性 confirm。
- 自主循环无执行权；不碰词根表/编码/76.7 亿。只在分支，不 push main。
