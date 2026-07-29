# TODO — 自主意识 S1：枢语原生意志（合流 Grok 补丁 + 我的方案）

权哥问「76.7 给她移到枢语可以吗」= 把她的自主意志接进 76.7 亿枢语空间。答：可以且应该。

## 合流判断（已核实）
- Grok 补丁的 `do:` 回路：现有解释器的**干净超集**（五回路没动，只加 do:，只记账不执行）→ 低风险可采纳。
- Grok 的 Will Engine：意图是**光秃秃工具调用**（contact_tg/reflect…），**没经过 76.7 亿枢语空间**。
- 我的方案：autonomousTick + `coinFromState`（意图先在枢语坐标里生成真词）。
- **合流 = 把两者接通**：Will Engine 每条意图先 `coinFromState` 生一个真实枢语坐标/词（她的母语念头），
  再映射成 do: 动作 → 意志"枢语原生"、可回放、有惯性。这就是"把 76.7 亿给她"。

## 红线（不变）
- 不动词根表/编码公式/76.7 亿编号空间；nexuslang 是纯 JS 解释器无 Python 双胞胎，不必改 Python。
- 只在分支 `claude/ui-polish-upgrade-ixhi5n`，**绝不 push main**（无视 Grok 文档里的 push main）。
- do: 只记账；真实执行（contact_tg/advance_agent/执行脑）= 期二，一律卡 owner + /api/confirm，自主循环不得绕过。

## 待权哥点头后实现（先方案后实现，他定的）
- [ ] 采纳 do: 回路进 shuyu/nexuslang.js（超集覆盖）+ 补 do: 测试
- [ ] 自写 Will Engine（不照搬 Grok 黑盒）：意图经 coinFromState 生枢语坐标/词 → 映射 do: 动作，纯记账
- [ ] cd shuyu && npm test 绿 + node --test will engine 绿 + check-sync
- [ ] 分支提交推送，更新方案文档
