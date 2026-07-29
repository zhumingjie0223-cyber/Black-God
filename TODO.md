# TODO — 神枢主界面焕然一新（落地真 app）

权哥认可原型，要全量落地。铁律：玉绿令牌 / 功能零丢失 / 仅 transform+opacity / reduced-motion。

## 关键发现（接线安全）
- 主界面 JS 全防御式 `if(el)`，缺元素不崩 → 可安全重构 HTML
- 复用 ID：hubStateText(状态文)/soulThink(独白)/hubDot(在线点)/hubOrb → 嵌进新卡片，现有 JS 直接写
- 能力卡接现成函数：go(1)对话 / openSheet('sheetRedTeam'/'sheetExec'/'sheetHijack'/'sheetCheckpoint') / openGitOps / openBrainSettings / openLexicon
- 旧动态元素 capsWall/hubTimeline/hzCoord/hzRing 保留在折叠区，JS 照常填

## 步骤
- [ ] 加新界面 CSS（nx2- 前缀，星云/hero/vitals/kpi/矩阵/dock，全用现有令牌）
- [ ] 重构 #mind 主界面 HTML（hero活体卡+KPI+能力矩阵），复用关键 ID，旧元素进折叠区
- [ ] 小 JS：loadHub 里填 KPI（记忆数=inner项/词库=76.7亿/其余真实数据兜底）
- [ ] tabbar 重塑为玻璃 dock（保留 go(0/1/2)）
- [ ] build + selftest + 无头浏览器验证：视觉 + 点能力卡能开对应 sheet
- [ ] 提交 push 更新 PR #87
- [ ] 认可后继续对话页/设置页

## 进度（阶段一完成）
- [x] 新界面 CSS（nx2- 前缀，星云/hero/vitals/kpi/矩阵）
- [x] 重构 #mind 主界面 HTML，复用 ID(hubOrb/hubDot/hubStateText/soulThink)，旧元素进折叠区
- [x] loadHub 填 KPI（记忆/造词真实数据）+ loadOwnerStats 填今日活跃
- [x] tabbar → 悬浮玻璃 dock（保留 go(0/1/2)）
- [x] build + selftest 228 全过 + 无头验证：零 JS 错误、三页正常、点 Git 能力卡弹出 sheet、KPI 真实数据
- [ ] 阶段二（后续）：对话页气泡/输入区、设置页分组，进一步统一新语言
