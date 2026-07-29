# TODO — UI 打磨升级（分支 claude/ui-polish-upgrade-ixhi5n）

- [x] 摸底：通读样式令牌与页面结构——玉绿设计系统已落地，含 Lovable 逆向阴影引擎 + OKLCH 色阶，成熟度高
- [x] 摸底：无头浏览器逐屏截图（条款/登录门/神枢/对话/设置）——设计整体精致
- [x] 定打磨清单：发现真实缺陷——左上角悬浮胶囊 `#statsPill`(在线统计) 与 `#pubApiBtn`(我的API)
      ① `left:12px;top:62px` 固定定位，跨页遮挡页面 eyebrow 小字（"THE HUB · 神枢"/"SETTINGS · 配置"）
      ② 硬编码石墨灰 `rgba(20,24,28)` + 银字 `#6FA985`，违反"沿用玉绿令牌"铁律，浅色主题会露馅
- [x] 动手：加共用 `.corner-pill` 令牌化样式类（右对齐消遮挡 + 玉绿令牌 + 入场淡入/按压回弹，仅 transform/opacity）；两处硬编码内联样式（statsPill/pubApiBtn）改为挂 class
- [x] 重新构建 `node build.mjs` + 自测 `node selftest.mjs`——228 passed, 0 failed
- [x] 校验双副本：手动核验构建产物已内嵌最新页面 + 含 corner-pill + 旧硬编码已清除（sync-ui --check 那条红是既有工具 bug，非本次引入，见总结）
- [x] 无头浏览器前后对比：eyebrow 从被遮挡→完整可见，胶囊移右上与 eyebrow 呼应
- [ ] 中文 commit + push 到指定分支 + 开草稿 PR
- [ ] TODO.md 写总结并归档到 docs/done/

## 总结

**本次做了什么**：UI 打磨——修复了跨页面的一处真实视觉缺陷。左上角两个悬浮胶囊
（主人模式的「在线统计」`#statsPill`、公共模式的「⚙︎ 我的 API」`#pubApiBtn`）原本用
`position:fixed; left:12px; top:62px` 固定在左上，正好压住每个页面左对齐的 eyebrow 小字
（"THE HUB · 神枢" / "SETTINGS · 配置"），跨页遮挡；且内联硬编码了石墨灰 `rgba(20,24,28)`
+ 银字 `#6FA985`，违反"沿用玉绿令牌不硬编码"铁律，浅色主题下会露馅。

**怎么改的**：新增共用样式类 `.corner-pill`——① 改为右上角定位，与左侧 eyebrow 左右呼应，
彻底消除遮挡；② 全部改用玉绿设计令牌（`--surface-2`/`--line-2`/`--text-2`/`--cy-3`/`--shadow-sm`），
深浅双主题自适应；③ 加入场淡入（`cornerPillIn`）+ 按压回弹（`:active{scale(.94)}`）微交互，
仅用 transform/opacity，并 `prefers-reduced-motion` 下关闭。两处 `createElement` 的内联
`cssText` 删除，改挂 `className='corner-pill'`（保留 id 供 JS 钩子）。

**验证**：`node build.mjs` 重建产物 + `node selftest.mjs` 228 项全过；手动核验 `nexus_do.mjs`
已内嵌最新 index.html+frontier、含 `.corner-pill`、旧 `#6FA985` 已清除；无头浏览器逐屏
对比确认 eyebrow 从"被胶囊压住乱码"变为完整可见、胶囊右上就位、质感与周围玻璃面板统一。

**顺带发现（未改，留给权哥定夺）**：`tools/sync-ui.mjs --check` 的「主界面」这条守护
改动前在 main 上就一直报红——它拿**未注入 frontier** 的 raw `index.html` 做子串比对，而
`build.mjs` 每次构建都会往 `</body>` 前注入 `nexus-frontier.css`，两者永远对不上，导致这条
守护实际恒红、失去作用。属既有工具 bug，本次为保持 PR 聚焦 UI 未一并修；建议后续单独修
（把校验逻辑改成"先注入 frontier 再比对"即可）。

