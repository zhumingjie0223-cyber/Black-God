# TODO — 按钮质感升级（常驻流光亮点）

分支 claude/ui-polish-upgrade-ixhi5n。权哥反馈：现有按钮 CSS 平淡、没亮点、没觉察。

## 诊断
- 按钮已有 hover/active/focus 效果（发光阴影/上浮/回弹/ripple），但**移动端无 hover**，
  静止态就是一块玉绿渐变+淡阴影，是"死"的 → 感觉不到亮点。
- 缺少**常驻微动态**（logo 已有流光呼吸，按钮却静止，对比下更显死气）。

## 方案（守铁律：玉绿令牌 / 仅 transform+opacity / reduced-motion 全关）
- [ ] 给主按钮（.btn / .lock-btn / .ob-btn）加常驻**玉绿流光扫过**（sheen sweep），
      呼应 logo 流光，形成统一设计语言；ghost 次要按钮不加
- [ ] .lock-btn/.ob-btn 补 position:relative + overflow:hidden 以裁切流光
- [ ] node build.mjs 重建 + selftest 自测 + 核验内嵌
- [ ] 无头浏览器验证（登录门解锁按钮 + 设置按钮）流光效果
- [ ] 提交 + push + 更新 PR #87 + TODO 归档
