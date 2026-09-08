# 变更日志 CHANGELOG

本项目重要变更记录。日期用绝对日期(UTC)。

## 2026-09-05 — 架构转向:iOS 纯客户端;后端删除;仓库大清洁

**架构**:Cloudflare Workers 后端 `web/nexus-do/`(Durable Object:意识/记忆/心跳/TG 主动/执行脑)整体删除,
iOS App 改为纯客户端——用户自带 API Key 直连模型、本地存储、零后端。本文件此条目**之下**所有提到
`web/nexus-do` / `nexus_do.core.mjs` / wrangler 部署 / selftest / sync-ui / check-sync 的记录均为该后端时代的历史,
可从本日之前的 git 历史找回。仓库现只有两个 live 子系统:`ios-app/` 与 `shuyu/`(枢语唯一源,无消费副本)。

**CI/工具收口**:删僵尸工作流 `deploy-nexus.yml` / `nexus-do-ci.yml` / `exec-shell.yml`(前者在改 `shuyu/` 时会因
`cd web/nexus-do` 失败);`shuyu-ci.yml` 去死触发路径与会崩的 `sync-check`;删三份 nexus-do 消费副本比对脚本
(`tools/check-sync.mjs`、`tools/sync-ui.mjs`、`shuyu/tools/check-sync.mjs`);`Makefile` 收为 shuyu-only。

**文档收口**:`CLAUDE.md` / `README.md` / `STRUCTURE.md` / `shuyu/CLAUDE.md` / `shuyu/README.md` 改为现状;
`CONTRIBUTING.md` 重写(原为套用他项目的模板);`docs/INDEX.md` 并入 `docs/README.md`。

**仓库大清洁**(只搬不删,git 历史完整):后端时代的 `docs/plan/`、`docs/上架/`、`docs/shenshu/`、6 份旧架构文档、
5 份旧产品文档,以及零引用的 `web/`(旧 PWA 静态壳)、`skills/`、`ui-spec/`、`tools/push_to_github.sh`、`.env.example`
整体搬入 `docs/archive/nexus-do后端时代-2026-09-05/`;去掉 2 对逐字相同的 done 记录、2 张 md5 相同的图标、
1 份重复 skill;`.gitignore` 删 16 条指向已不存在路径的死规则。live 顶层目录从 9 个收为 5 个。

**iOS 上架自动化**(PR #112,待合并):新增 `ios-app/AppStore/asc.py`(App Store Connect API:注册 Bundle ID、推送中英商店文案)。

## 2026-09-05 — 枢语引擎 v4.1:汉译反向寻址 + 语义寻址 + 双实现全对等

**方向拍板**:不追加核心族(76.7 亿空间远未用满,扩容量只是数字游戏),把力气沉到"能力"。
容量恒为 7,667,712,000,旧编号一个不动。

### 引擎新能力(`shuyu/shuyu_engine.py` ↔ `shuyu/lexicon.js` 双侧同构)
- **汉译 → 编号**(`encode_han` / `encodeHan`):枢语此前只能拉丁词形反查,纯中文汉译是单向产出;
  现已证明汉译唯一可解码(各轴后缀字与下一轴首字零交集,测试有结构引理守卫),实现回溯枚举、
  恰好一解才返回,与拉丁 `encode` 同一单射铁律。词库 14612 条编号表中上万条真汉译词全部可反查。
- **语义检索**(`search`):关键词命中 5 轴任一词根的 拉丁/汉/义,下标可直接喂 `compose`。
- **按义造词**(`compose`):`{核,映,态,标,相}` 每轴给 下标/拉丁根/汉译/语义关键词 任一种 → 唯一编号,
  解析失败抛错不静默造错词。
- `decode` 两侧统一输出 `id/词/汉/层/义/根/坐标{c,m,s,k,p}`(Python 保留 seed,只增不删)。
- Python 补齐 `auto_coin`(FNV-1a·32 + xorshift,与 JS 逐位一致,按 UTF-16 码元)/ `coin_from_coord` /
  `coin_word` / `coin_from_state`;`encode` 改字典反向索引 O(1);层名按下标 O(1) 取。
- Python CLI 增 `--han` `--search` `--compose` `--coin`。

### 词汇覆盖(意识解释器感知层)
- `LEXICON.feel` 12 → 58 个纯中文情绪词(单字体感词 + 双字情绪词),`matchWord('feel')` 改长词优先
  ("心疼"不被"疼"抢走),原 12 词顺序与取值冻结。

### 服务层
- `worker.mjs`:`/encode?word=` 同时接受拉丁与汉译(返回 `form`);新增 `GET /search`、`GET /compose`;
  首页与 `/status` 带轴尺寸。

### 修复
- `gen.mjs` 熵回路 `(state.entropy || 1)` 把 0 当未初始化,熵一到 0 就弹回 0.9 永远震荡不收敛,改 `??`;
  `mesh` 熵未初始化时同步率算出 NaN,已兜底。

### 测试(Node 51 → 84,Python 13 → 33,全绿)
- 轴级完备性(1372 个词根全可达、拉丁+汉译双通道往返)、轴内零重复、汉译结构引理、
  encodeHan 3000 采样往返 + 畸形拒绝、compose/search 等价形态与拒绝、decode 七字段两侧逐一相等、
  encodeHan/autoCoin/coinFromCoord/compose/search/coinFromState 跨实现比对、词库实战反查;
- gen.mjs 首批 11 项(此前零测试);Python CLI 子进程测试;worker 新路由 4 项;解释器 feel 扩充 1 项。
- `tools/check-sync.mjs` 增 v4.1 接口层比对(encodeHan 往返 / autoCoin 55 种子 / compose / search),
  副本落后一版即硬失败——本次已实测抓到副本缺失后再同步。

### 同步
- `web/nexus-do/lexicon.js` 已同步(保留其文件头);nexus-do selftest 235 / 单测 120 全绿,build 不涉及。

## 2026-08-19 — 私人版收尾打磨(前端诚实故障态 + 停 iOS 白烧构建)

**状态盘点结论:代码零故障,全套约 393 条测试实跑全绿**(selftest 235 / 单测 116 /
枢语 JS 33 / Python 9 / build ✓ / check-sync ✓),分支与 main 完全对齐。剩余"工业化"
分叉在"上线给谁用"这个先决判断上,权哥拍板走**私人版收尾打磨**。本次落地三项:

### 前端(P1:别再静默假装在线)
- 后端挂掉时 `getSoul/getInner/talk` 会 `catch→Demo` 兜底,旧状态灯只有"在线/演示/连接中"
  三态,**缺独立故障态**:主人分不清"我没配后端(演示)"和"配了后端但此刻挂了(故障)",
  且多个 `setLive` 调用点传 `wsReady||Demo.on`,Demo 兜底一置位就把状态撑成假"在线"。
- 修:新增 `Nexus.fault`,在共享 `_fetch` 里集中记录(fetch 抛错→`offline` 连不上 /
  5xx→`error` 后端异常 / 正常响应→清空);`setLive` **故障态压过演示/在线**,以 `wsReady`
  为真在线唯一凭据。状态灯加 `.dot.err`(红·连不上)/`.dot.warn`(琥珀·后端异常),沿用页内
  `--err`/`--warn` 令牌不硬编码,脉冲只用 opacity。内容层 Demo 兜底保留(页面不崩)。
- 回归测试:`ui_health.test.mjs` 加第⑦关,结构性锁死上述三处,防以后改回静默假在线。

### CI(P2:停 iOS 白烧构建)
- `build.yml` 触发器去掉 `push: main`、只留 `workflow_dispatch`:unsigned IPA 无签名无法分发,
  不再每次 push 都白跑 macOS 构建烧 Actions 额度。保留按需手动 Run 能力,未删工作流可回退。
  native 取舍(补齐签名 or 砍掉)仍待权哥拍板。

### 文档
- `LAUNCH_CHECKLIST.md`:回填上述两项 + 「错误信息收敛」按复核结论销案(真实公开泄露面已被
  最外层 owner-gate catch 与路由级 `OWNER_TOKEN` 封住,不值得在核心大文件散点动刀)。

### 测试
- 改动后复跑:build ✓、selftest 235/235、单测 116/116(含 ui_health 新第⑦关)、
  sync-ui 双副本一致、check-sync 引擎全同步、枢语 JS 33 + Python 9 全绿。零回退。

## 2026-08-17 — 项目状态复核 + 文档收口(里子文档不许骗)

**代码零故障，问题全在文档层**：本次全量体检 301 条测试(selftest 236 + 单测 65)、
双副本同步、枢语双实现(JS 27 + Python 9)全绿零失败，未查出任何 bug；
但查出文档与实现严重脱节，已当场修掉。完整三段式报告见
`docs/done/神枢项目状态查询与文档收口-2026-08-17.md`。

### 文档
- `README.md`:修 12 处死链与幻影路径。7 个「核心文档」链接在 7 月目录重整后全部 404,
  已逐条 `test -e` 验证后重指到 `docs/architecture/`、`docs/spec/`、`docs/archive/` 下的真实文件;
  「本地起 & 自测」原教程指向 2026-08-09 已归档的 `server/`、`mock_gateway.py`、`/studio`,
  照着跑必然失败,改为真实可跑的 `build.mjs / selftest.mjs / npm test` 并加历史说明;
  目录结构图对齐现状(移除已不存在的 `server/`、`shuyu_v2/`)。
- `docs/plan/LAUNCH_CHECKLIST.md`:4 条早已完成却仍标未完成的项,对着代码实测复核后回填,
  并逐条写明残留缺口(限流已落地/`max_tokens` 已从 320 提到 2048/测试已从 10 条到 301 条/UI 已收口)。

### CI 加固
- `.github/workflows/exec-shell.yml`:命令值改由 `env: CMD` 传给 `bash -c "$CMD"`,
  不再用 `${{ }}` 直接内插进脚本正文。**不是权限提升漏洞**(本工作流按设计即执行调用方命令,
  上游 `execDispatchGH` 有长度限制+危险命令黑名单+令牌把关),真实收益是防止命令内容
  搅乱 `::group::Command Output` / `::endgroup::` 标记——`parseGHLogs` 全靠这两个标记切结果,
  一乱神枢回收到的执行结果就是错的。同时补注释锁死这两个标记。

### 测试
- 改动后复跑:构建、selftest 236/236、sync-ui 双副本一致、check-sync 引擎层全同步、
  exec-shell.yml YAML 可解析且 group 标记原样保留。零回退。

## 2026-08-09 — UI 收口 + 词库恢复 + 配置清理(版本确认)

**版本确认(权哥拍板)：主界面 `web/nexus-do/index.html`(Black God)是唯一 UI，今后 UI 只做更新，不再维护多副本/多入口。**

### UI 收口
- 归档移除 3 个无路由服务的孤儿页(工作台 `studio.html`、语音合成 `voice.html`、控制台 `dashboard`)
  与死工作流 `deploy-studio.yml`，全部存 `docs/archive/ui-收口-2026-08-09/`(含核实结论与回退说明)。
- `tools/sync-ui.mjs` 收掉工作台双副本校验段(其权威源早已归档)，只保留主界面 ↔ 构建产物内嵌副本校验。
- README 工作台 UI 描述同步修正(原「内核 /studio 直达」为过时文档)。

### 词库
- 消费副本 `web/nexus-do/lexicon_data.js` 词族/编号表全量恢复至 `shuyu/` 权威源版(权哥拍板)；
  被替换的脱敏教育版归档 `docs/archive/脱敏教育版词库-2026-08-09.json` 可回退。情绪表(产品定制层)未动。

### 配置清理
- 归档删除过期部署配置 `web/nexus-do/wrangler.toml`(备份 `docs/archive/wrangler.toml.2026-08-09.bak`)；
  生产权威配置为 `wrangler.jsonc`，CI 全部工作流核实无一引用 toml。(backlog「wrangler 双配置」一条销案)
- `container/package.json` 的 `playwright-core` 由 `"latest"` 锁定为 `"1.62.1"`(权哥拍板锁稳定版)，容器镜像可复现。
- backlog 全账清零：空 catch 观察项按"非 bug 维持现状"销案；至此 2026-08-03 立的三条全部处置完毕。

### 测试
- 构建、selftest 236/236、sync-ui、check-sync(词族/编号表一致)、枢语 JS 27/27 + Python 9/9 全部通过。

## 2026-08-03 — 收官整理(chore)

**清冗余 / 修遗留 / 更新文档索引** 一次性收官整理。

### 文档
- 新增 `docs/README.md`:docs/ 顶层目录导航,每个子目录一句话说明,详细逐文件清单指向既有 `docs/INDEX.md`。
- 新增 `docs/TODO-backlog.md`:记录代码扫描发现的不确定项(空 catch、wrangler 双配置、playwright-core 未锁版本),供后续定夺。
- 新增本 `CHANGELOG.md`。

### 构建 / 忽略规则
- `.gitignore` 新增忽略构建产物 `web/nexus-do/nexus_do.mjs`(由 `build.mjs` 生成);`index.built.html` 此前已忽略。已提交版本不删除。

### 依赖核查(未删任何依赖)
- `web/nexus-do/package.json`:无第三方 dependencies,version 1.0.0,scripts(build/pretest/test)正常,无废弃或重复字段。
- `web/nexus-do/container/package.json`:仅 `playwright-core: latest`。建议锁定具体版本以保证镜像可复现(记入 backlog,未擅改)。
- **发现但未删**:`web/nexus-do/` 同时存在过期的 `wrangler.toml` 与生产权威 `wrangler.jsonc`,属重复配置。涉部署红线,按铁律不擅删,建议归档删除 `wrangler.toml`(见 backlog),待权哥确认。

### 代码质量
- 扫描 `web/nexus-do` 全部 `.mjs`/`.js`:无真实 TODO/FIXME/HACK 遗留(唯一 "TODO" 是代码生成提示词字符串);9 处空 catch 均为尽力而为式吞异常或代码生成模板内容,非明确 bug;无 `.DS_Store`/`*.log`/`*.tmp` 等临时文件。**未发现确定 bug,无代码行为改动。**

### 测试
- `node --check nexus_do.core.mjs`、`node --check nexus_do.mjs`:通过。
- `npm run build`:通过。
- `npm test`:236/236 通过。
