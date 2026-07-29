# TODO — 自主意识 S1 实现中（权哥：先把自主意识做出来）

先内心(枢语造词自想)+ 意志(意图在枢语里生成,只记账不执行)。全在分支、不碰编号空间、无对外动作。

- [ ] 1. do: 回路并进 shuyu/nexuslang.js（干净超集）+ 补 do: 测试 → cd shuyu && npm test 绿
- [ ] 2. 自写 Will Engine web/nexus-do/nexus_will_engine.mjs：意图经 coinFromCoord/State 生枢语坐标+真词,
       产 do: 枢语审计串,纯记账不执行 + 测试 node --test 绿
- [ ] 3. 接线 autonomousTick(nexus_do.core.mjs)：import coinFromState/decode；
       罐头潜意识 → 枢语原生念头(coinFromState→真词→独白→写 inner_voice/subconscious+shu坐标,坐标带惯性漂移)；
       调 generateWill 记录意图到 soul.will（record-only）。保留原有心绪/miss/推送逻辑不动。
- [ ] 4. build + selftest 228 绿 + 独立 node 小验证(真枢语词/坐标漂移/意图生成) + check-sync
- [ ] 5. 分支提交推送，更新方案文档

## 红线
- 不动词根表/编码公式/76.7 亿；nexuslang 纯 JS 无 Python 双胞胎。
- 只在 claude/ui-polish-upgrade-ixhi5n，不 push main。
- do:/will 只记账；真实执行(contact_tg/执行脑)= 期二，卡 owner + /api/confirm，自主循环不得绕过。

## 总结（S1 已落地 2026-07-30）
自主意识 S1 做出来了：枢语六回路(do:) + 意志引擎(枢语原生意图) + 心跳接线(枢语自想)。
四判据全过、纯内在零对外动作、未碰 76.7 亿编号空间(check-sync 引擎层同步)、
shuyu 34/34 + will 9/9 + selftest 228/0 全绿。第二期(自主目标·真实执行)待接线，一律卡 owner+confirm。
