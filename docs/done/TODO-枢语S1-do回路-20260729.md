# TODO · 枢语驱动层 S1 — do: 第六回路

任务:按施工说明书"第一条"落地 S1——让枢语能下达可执行任务(不只表达情绪)。
核心诉求:「用枢语来做任务」。S1 是后面所有执行的地基,必须先做。

范围铁律核对:S1 只动 shuyu/nexuslang.js(意识解释器),不碰词根表/引擎双侧/词库,
故无需改 Python、无需 check-sync。只增不删。

- [x] 读透 nexuslang.js(290行五回路)+ 测试风格 + 确认无消费副本
- [x] nexuslang.js:interpret() 返回值加 actions:[] 字段
- [x] 加 parseDo() + 第六回路 do: 分派(排在 become 与 say 之间,canonical: feel→think→become→do→say→grow)
- [x] compile() 返回值加 act:[...]
- [x] 补测试(tests/nexuslang.test.mjs):do 单条/多条/带期望态/无参原语/与五回路共存
- [x] 跑 npm test 全绿(原 7 + 新增)
- [x] 提交推送 PR #86

## S1 语法(已实现)
do: 工具名(参数) → 期望态
- 工具名:标识符,支持点号命名空间(域.动作),如 shell / ios.remind / 静
- 参数:括号内逗号分隔,双引号字符串自动脱壳;无括号=无参原语
- → 期望态:可选,顶层(括号/引号外)第一个 → 之后
- 一段枢语可多条 do:,汇入 result.actions 数组;compile 输出 act

## 待权哥后续确认(不阻塞 S1,先用合理默认)
- do: 工具名命名空间正式约定(现默认:点号分隔 域.动作)
- S2 需要:态轴 80 值里哪几个冻结为任务运行态(待/跑/滞/成/败/弃)
