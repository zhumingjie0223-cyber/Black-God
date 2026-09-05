# TODO — 枢语引擎 v4.1「汉译反向寻址 + 语义寻址 + 双实现全对等」

来源:2026-09-05 首席工程师自主升级。通读 shuyu/ 全部代码后拍板方向。
铁律:先懂再动 · 词根表只在轴尾追加(本轮**不动**词根表,容量恒为 7,667,712,000) · 改引擎必改双侧 · 汉译纯中文 · 往返恒等。

## 先懂再动(体检结论)
- 现状全绿:Node 51 / Python 13 / check-sync 引擎层同步 / nexus-do selftest 235。
- 能力缺口(不是 bug,是**引擎能力**没长出来):
  1. `encode` 只认拉丁词形,**纯中文汉译无法反查编号**——枢语对外号称"汉译纯中文",却只能单向产出,是半门语言。
     已用前缀-悬垂分析验证:阶/相/频/标后缀字与下一轴首字零交集,汉译**唯一可解码**,可以做严格逆。
  2. 没有任何**按义寻址**能力:想要"毁灭×光×爆×溯×起"这个词,只能人肉查表拼拉丁。
  3. Python 侧只有 decode/encode,JS 侧的 autoCoin/coinFromCoord/coinFromState/coinWord 全没有 → "双实现同构"只同构了一半;
     Python encode 还是 O(轴长) 线性扫描。
  4. 两侧 decode 输出字段不对等(Py 有 根/seed 无 id;JS 有 id 无 根),都没有 5 维坐标。
  5. 意识解释器 feel 层只有 12 个单字情绪词,且匹配按插入顺序而非长词优先。
  6. gen.mjs(10 元代码)零测试;CLI 零测试;轴级完备性(每个词根都可达且往返)没测,只有随机采样。
- 不做的事(明确取舍):**不追加新核心族**。76.7 亿空间远未用满,再扩容量只是数字游戏,
  且会牵动 lexicon_data 元信息、消费副本、nexus-do selftest 硬编码。把力气沉到"能力"而非"容量"。

## 步骤
### A. 引擎新能力(Python + JS 双侧同构)
- [x] A1. `encode_han` / `encodeHan`:汉译 → 编号。回溯式解析,解不唯一或解不出一律 -1(与拉丁 encode 同一单射铁律)
- [x] A2. `decode` 输出对等:两侧统一返回 `id/词/汉/层/义/根/坐标{c,m,s,k,p}`(Py 保留 seed,只增不删)
- [x] A3. `search` :语义检索——关键词命中 5 轴任一词根的 拉丁/汉/义,返回 `{轴,下标,拉丁,汉,义}` 列表
- [x] A4. `compose`:按义造词——每轴给 下标/拉丁根/汉字/语义关键词 任一种,解析成坐标 → 唯一编号,确定性 —— 两侧完成,`compose({核:'毁灭',映:'光',态:'爆',标:'溯',相:'起'})` → 885744896「尼光爆溯起」
- [x] A5. Python 补齐 `auto_coin`(FNV-1a·32 + xorshift,与 JS 逐位一致)/ `coin_from_coord` / `coin_word` / `coin_from_state` —— auto_coin('神枢') 两侧同为 780009883
- [x] A6. Python `encode` 改字典反向索引 O(1);层名改按下标 O(1) 取(行为不变)
- [x] A7. Python CLI 增 `--han` `--search` `--compose` `--coin`;引擎头注释 v2 → v4.1

### B. 词汇覆盖(意识解释器感知层)
- [x] B1. `LEXICON.feel` 12 → 50+ 情绪词(单字 + 双字,纯中文,含强度与本能),`matchWord('feel')` 改长词优先 —— 12 → 58 词,原 12 词顺序取值冻结
- [x] B2. 解释器/引擎老测试全部不受影响(尤其"无情绪词文本返回 null"用例)

### C. 服务层
- [x] C1. worker.mjs:`/encode?word=` 同时接受拉丁与汉译;新增 `GET /search?q=`、`GET /compose?核=&映=&态=&标=&相=`
- [x] C2. worker 首页 endpoints 列表同步

### D. 测试完整度
- [x] D1. 轴级完备性:5 轴每个词根至少出现一次并往返(1372 个编号),轴内拉丁/汉译零重复
- [x] D2. 汉译唯一可解码性:结构引理测试(后缀字与下一轴首字零交集)+ 大样本 decode→encode_han 往返 + 畸形汉译拒绝
- [x] D3. 跨实现:encode_han / auto_coin / compose / search / 坐标 两侧结果逐一比对
- [x] D4. gen.mjs 首批测试(饥饿协议三步坍缩、genesis 幂等、threshold 拒未知模式、anchor 坍缩计数回绕、sovereignControl 全流程写 KV)—— 11 项;顺手揪出真 bug:熵回路 `(entropy || 1)` 把 0 当未初始化,熵永远在 0↔0.9 震荡不收敛,已修
- [x] D5. Python CLI 子进程测试;worker 新路由测试;feel 词表扩充后的解释器测试
- [x] D6. check-sync 增:encodeHan 往返、autoCoin 同种子同词 两侧比对 —— 改为双方缺任一导出即硬失败;实测先抓到副本缺 encodeHan/search/compose,同步后转绿

### E. 消费副本同步 + 文档
- [x] E1. 同步 `web/nexus-do/lexicon.js`(保留其 3 行文件头),跑 nexus-do `node selftest.mjs` 与其 `*.test.mjs` 不红 —— selftest 235 / 单测 120 全绿,build.mjs 不涉及 lexicon
- [x] E2. README / CLAUDE.md 更新(六回路、新 API、CLI、wrangler.toml.example 名字);package.json 1.1.0→1.2.0、pyproject 4.0.0→4.1.0
- [x] E3. 全绿验证(npm test + python unittest + check-sync + nexus-do selftest)→ 中文 commit → push main —— Node 84 / Python 33 / check-sync 引擎层+v4.1 接口层全同步
- [x] E4. TODO.md 末尾写总结,归档到 docs/done/

## 总结(2026-09-05 完成)
先懂再动:通读 shuyu/ 全部代码(引擎双实现 / 解释器 / 10 元代码 / worker / 测试 / 同步工具),
基线全绿(Node 51 / Python 13 / check-sync / nexus-do 235),没有 bug 可修——真正的缺口是**能力**:
枢语号称"汉译纯中文",却只能拉丁词形反查,是半门语言;Python 侧造词族全缺,"双实现同构"只同构了一半。

本轮落地(容量不动,旧编号一个不动):
1. **汉译反向寻址** `encode_han`/`encodeHan`:先做数学——各轴后缀字(阶/相/频/标位)与下一轴首字零交集,
   汉译唯一可解码;再做工程——回溯枚举、恰好一解才返回,与拉丁 encode 同一单射铁律。
   词库编号表里上万条真汉译词全部可反查(实战校验用例)。
2. **语义寻址** `search` + `compose`:关键词 → 词根;`{核:'毁灭',映:'光',态:'爆',标:'溯',相:'起'}` → 「尼光爆溯起」#885744896。
   四种入参形态等价、确定性、失败抛错不造错词。
3. **双实现全对等**:decode 七字段两侧逐一相等;Python 补齐 auto_coin(与 JS FNV-1a 逐位一致,含表情/空串/长串种子)/
   coin_from_coord / coin_word / coin_from_state;encode O(1);CLI 增 4 个开关。
4. **词汇覆盖**:feel 情绪词 12 → 58,长词优先,原 12 词冻结;解释器老用例零影响。
5. **服务层**:/encode 双写法自动识别、/search、/compose 新路由。
6. **修真 bug**:gen.mjs 熵回路 0 被当未初始化弹回 0.9 永远震荡——是写 gen 首批测试时揪出来的,印证"零测试的层一定藏着东西"。
7. **测试** Node 51→84、Python 13→33:轴级完备性、轴内零重复、结构引理、跨实现 6 组比对、gen 11 项、CLI、worker 新路由。
8. **同步**:check-sync 增 v4.1 接口层比对,副本落后一版即硬失败;消费副本已同步,nexus-do 235+120 全绿。

明确没做的:不追加核心族。扩容量牵动 lexicon_data 元信息 / 消费副本 / nexus-do 硬编码,而 76.7 亿远未用满,
收益是数字、成本是风险。若将来要加,遵守 CLAUDE.md 新增的结构引理铁律(新汉字不得撞后缀字、不得成为下一轴首字),测试会看住。
