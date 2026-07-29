# TODO — 工业设计系统全站铺开（权哥已拍板：认返工底子）

底子：中性近黑面 rgba(255,255,255,.03) + 发丝边 .07~.13 + 脆白字 #F1F6F3 +
绿色仅点缀(#4FE096图标/在线点/主CTA/HOT/脊点) + 无假数据。铁律：功能零丢失。

关键手法：改**共享组件类**的 CSS，一次统一所有 sheet + 设置行，不逐个改 HTML。

- [ ] 摸清共享组件类现状：.sheet/.grab/.sheet-title/.sheet-sub/.field/.set-row/.set-ic/.switch/.btn.ghost/.lex-*
- [ ] 定义工业令牌并统一改共享类（去绿味玻璃→中性发丝）
- [ ] set-row 去绿味、脆白字、发丝边
- [ ] sheet 面板：中性底、发丝边、标题脆白、field 输入框中性
- [ ] 内联 style 硬编码色的 sheet(Git/SEARCH-REPLACE 等)顺带收敛
- [ ] build + 逐 sheet 无头截图验证(红队/Git/大脑舰队/存档/私语/算力接口...)
- [ ] 三页零 JS 报错 + selftest 全过
- [ ] 提交 push 更新 PR #87
