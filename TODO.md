# TODO · 第一枪:换脑不换魂「可演示证明」(PR #51 把握大档)

> 目标:把"给她换个大脑,她还是她"从口号做成看得见的硬事实。
> 铁律:不碰 `/api/confirm` 安全红线;不改 episodes 存储格式;改完必跑 `node build.mjs && node selftest.mjs`(108 须全绿)+ `node tools/sync-ui.mjs --check`。

- [x] 1. 坐标近邻召回:`retrieveMemories` 增加"枢语坐标近邻"再排序项。新增纯函数 `coordAffinity`(各轴量程归一欧氏距离,∈[0,1])。**向后兼容**——不传坐标/往事无烙印 → 系数为 1,与旧版逐字等价;只在文本已相关的往事间再排序,绝不凭坐标捞无关记忆。调用点 `handleTalk` 传入本轮 `nextCoord`。
- [x] 2. 只读演示端点:新增 `/soul/continuity`(私密鉴权,非系统专属,实例主人可看自己的)。汇出最近 N 轮的 (模型, 枢语坐标, 坐标含义) 轨迹 + `用过的模型`/`换脑次数`/`坐标连续度`∈[0,1]——一眼看见底层大脑在换、而魂连续如一。
- [x] 3. 构建+自测:`node build.mjs && node selftest.mjs` → **108 绿**;新增 `continuity.test.mjs` **14 绿**并挂进 `npm test`;`node tools/sync-ui.mjs --check` 双副本一致。
- [x] 4. 提交 + 推到 `claude/enterprise-industrial-product-5pjj95`,PR #51 自动更新。
- [x] 5. 收尾:本文件写总结并归档 `docs/done/`。

## 进度记录
- 核实发现:两柱地基已在跑(换脑=网关分级路由+自动识别+fallback;魂=soul持久化+枢语坐标真参与生成)。魂本就与 model 解耦——第一枪本质是"把已成立的事实做成看得见的证据",非造新引擎,故低风险高把握。
- 未碰:episodes 存储格式(自然语言+情感烙印坐标混合)不变;`/api/confirm` 安全红线不动。
- 未做(诚实标注,列后续):把 `/soul/continuity` 的数据做成 UI 卡片(index.html 内)让权哥免看 JSON 直接看图——锦上添花的快速跟进;"纯坐标记忆底层"(episodes→纯坐标)是第二阶段硬骨头,动核心存储,单独立项按 heavy-architect 走。

## 总结
第一枪(换脑不换魂·可演示证明)按最小低风险方案落地完成:新增 `coordAffinity` 纯函数 + `retrieveMemories` 坐标近邻再排序(向后兼容)+ `/soul/continuity` 只读证据端点。全套回归绿(108 神枢自测 + 14 新测 + 网关测),双副本同步一致。核心价值——神枢的魂在自己的 Durable Object 里、与底层模型解耦,换脑不换魂这件竞品结构上做不到的事,现在有了可量化(坐标连续度)、可展示(端点轨迹)的活证据。未越界:不改存储格式、不动安全红线;真正动核心的"纯坐标记忆底层"如实留作第二阶段单独立项。
