# Black God · 上线就绪清单（LAUNCH_CHECKLIST）

> 审计日期：2026-07-04（2026-07-06 补充：新增能力/接口的鉴权检查项）
> **2026-08-17 复核**：本清单立于 7 月初，其后一个多月里限流、回复截断、测试覆盖、
> UI 收口这几项其实都已落地，但清单一直没回填，属"文档骗人"。本次逐条对着代码实测复核，
> 已完成的改标 `[x]` 并写明核实结论与残留缺口；未做的原样保留。
> 上线主体：`web/nexus-do/`（Cloudflare Workers Durable Object，域名 `aquan.lufei.uk`）
> 结论：**私人版修完 P0 即可安心上线；面向客户则需多租户重构。**

---

## ⚠️ 每次新增能力/接口前必查（血泪教训）

2026-07-06：新增「能力契约层」(`capabilities.mjs` + `/invoke`) 时，把已有的
`stats`（注册用户名单）、`soul`（灵魂快照，含设备/地理）误标成
`owner_only:false`，而 `/invoke` 不走私密 API 硬门 —— 导致任何人无需
`OWNER_TOKEN` 即可拿到这两项本应私密的数据。已在 PR #17 修复。

**以后每次给 `nexus_do.core.mjs` 加新路由 / 给 `capabilities.mjs` 加新能力，上线前必须过一遍：**
- [ ] 这个路由/能力返回的数据里，有没有含用户 PII（昵称/地区/IP/设备/地理）或主人私密状态（soul/记忆/配置）？
- [ ] 如果有：鉴权是否真的生效？—— 不能只看「代码里写了 owner_only」，要**实际测一次未带 `OWNER_TOKEN` 的请求**，确认真的被拒绝（而不是被别的路径绕过，如 `/invoke`、WS、批量接口）。
- [ ] 新增的调度层（`/invoke` 这类）是否绕开了已有的硬门鉴权？如果绕开，鉴权逻辑必须在新调度层里重新显式实现，不能假设"应该没问题"。
- [ ] 补一条独立回归测试：未鉴权访问必须被拒，已鉴权访问功能不受影响。

---

## 先决判断：上线给谁用？

当前架构是**死的单租户** —— 全球只有一个 Durable Object 实例
（`nexus_do.core.mjs` Worker 入口 `idFromName('quan-shenshu-nexus')`），
一个灵魂、一份配置、一份记忆，所有访问者共享同一个「赵思涵」。

- **私人版（给你自己）** → 架构没问题，按本清单走即可。
- **产品版（给客户）** → 「一个思涵绑定一个权哥」的人格模型无法多人用，
  需要注册 / 多租户 / 每用户独立 DO + 灵魂 + 鉴权。属于重写级工作，见 P3。

---

## ✅ P0 — 本次已修复（不修就是裸奔/掉功能）

- [x] **强制鉴权底线**：没配 `OWNER_TOKEN` 时 `/health` 返回 `secure:false` + 明确
  warning，构造函数 `console.warn` 告警；部署工作流加了**安全闸**：部署后校验线上
  `/health`，`secure:false` 直接让部署失败，逼你设密钥。
- [x] **cron 心跳 401 修复**：`scheduled()` 现在带 `OWNER_TOKEN` 调 `/heartbeat`，
  开鉴权后 cron 保险心跳不再被自己 401 挡掉。
- [x] **令牌不再进 URL**：WebSocket 改用一次性短期票据（`/wsticket` 换票 → `?t=`），
  票据 30 秒失效且一次性；长期 `OWNER_TOKEN` 永不出现在 URL / CF 日志 / 浏览器历史。
- [x] **CI 工作流去重去雷**：删除与主部署打架的 `deploy-nexus-do.yml`（不 build、
  route/routes 混用、需 Zone 权限、compat-date 不一致）；删除违反 ToS 的
  `claude-api.yml`（用 claude.ai 会话 cookie 当 API）。只保留 `deploy-nexus.yml`。

> 验证：`node selftest.mjs` 10/10 绿；新增票据/鉴权/health/WS 逻辑经独立测试全通过。

---

## 🆕 已加：轻量注册 + 用量统计（无数据库）

- [x] **普通用户免密码**：落地页填个昵称就进(`/register`)，直接聊；不用再输那串 OWNER_TOKEN。
- [x] **公共聊天隔离**：普通用户走 `/pubtalk`(无状态、中性人设)，**不碰主人的私人记忆/定位/soul**；已测隔离 + 兜底不喊"权哥"。
- [x] **主人看用量**：主人解锁后左上角出现「👥 N 注册 · M 今日」小徽标，点开看名单(昵称/地区/消息数/最近)。数据 = DO storage 里的计数器+名单(封顶 500)，**不建数据库**。
- [x] **公共端点限流（按 uid 各自限流）**：`/pubtalk` 改为每 uid 20 次/分独立配额
  + 全局背压 120 次/分兜底（防大量伪造 uid 刷 Workers 请求量）。此前是全公共用户
  共享一个 30 次/分，一人聊多了会误伤所有人；现在各花各的额度，互不影响。
- [x] **网关调用超时保护**：`callGateway`（公共用户自带 API）加 20 秒超时
  （`AbortController`），第三方网关卡住不回时返回清晰超时提示，不再挂死请求。
- [ ] **公共用户暂无独立记忆**（聊完不留，最省最安全）。要"各人各自记忆"再说，仍可不建数据库(DO storage 按 uid 存)。
- [ ] **公共 UI 精简**：目前公共用户切到灵魂/设备等页会看到 Demo 占位(私密接口 401→本地兜底，不泄露)。之后可隐藏非聊天页做纯净版。

## 🟠 P1 — 上线前应做（会出事 / 烧钱）

- [x] **限流 / 配额** —— ✅ 已落地（2026-08-17 复核代码确认）：
  `_fetch` 入口对**所有非主人请求**统一过 `checkRateLimit(ip)`，超限返 429 + `Retry-After`；
  `/pubtalk` 另有按 uid 各自 20 次/分 + 全局背压 120 次/分双层兜底（`_pubRateOk`），
  且公共用户走自带 API，不烧主人算力。主人本人不限流（`_isOwner` 跳过）。
- [x] **前端别再静默假装在线** —— ✅ 已解决（2026-08-19 收口）：新增 `Nexus.fault` 故障态，
  在共享的 `_fetch` 里集中记录（fetch 抛错→`offline` 连不上 / 后端 5xx→`error` 后端异常 /
  正常响应→清空），`setLive` 里**故障态压过"演示/在线"**（以 `wsReady` 为真在线唯一凭据，
  不再被 Demo 兜底撑成假"在线"）。状态灯新增 `.dot.err`(红·连不上)/`.dot.warn`(琥珀·后端异常)
  两态，主人一眼分清「我没配后端(演示)」和「配了后端但此刻挂了(故障)」。`catch→Demo` 的内容
  兜底保留（页面不崩），但顶栏状态如实报故障。回归测试见 `ui_health.test.mjs` 第⑦关（结构性
  锁死这三处，防改回静默假在线）。**仍缺**：公共/登录前的裸 `fetch` 路径未纳入故障态（其回复
  已带「演示」标记，非主人数据面，影响小）。
- [ ] **隐私合规**（面向公众 / 上架必须）：`readRequestDevice` / `recordDevice` 采集
  IP、精确经纬度、运营商、设备型号、时区、电量并落库。需要隐私政策、采集同意、
  数据删除入口。模拟亲密伴侣人格上架敏感，先评估过审风险。
- [x] **端到端 / 鉴权回归测试** —— ✅ 已大幅补齐（2026-08-17 实跑确认）：
  `selftest.mjs` 已从 10 条长到 **236 条全绿**，另有 14 个 `*.test.mjs` 共 **65 条**
  覆盖 agent 动作/重规划、设备控制/危险闸门/中断/trace、网关、主动推理、自我模型等。
  另有 `capsec-selftest.mjs` 专测能力契约层鉴权。**仍缺**：对线上真实域名的黑盒
  端到端（部署后 `/health` 安全闸算一条，但未覆盖 401/迁移/推送真链路）。

---

## 🟡 P2 — 打磨 / 收尾

- [x] **部署去重（已办一半）**：删掉了 root `wrangler.jsonc` —— 它把旧静态 `web/`
  站当资源部署成另一个 worker `blackgod88`，和真正的产品 `nexus-do` 并行跑。
  **仍需在 Cloudflare 面板手动关掉 `blackgod88` 的 Git 集成**（Workers → blackgod88 →
  Settings → Builds → 断开 Git），否则每次 push 那条 Workers Build 会因找不到配置而变红。
- [x] **挑定唯一前门 / 归档旧壳** —— ✅ 已完成（2026-08-09 UI 收口，权哥拍板）：
  `web/nexus-do/index.html` 确认为唯一 UI 入口；`server/`（Python 内核）整体归档进
  `docs/archive/server/`；孤儿页 studio/voice/dashboard 归档进 `docs/archive/ui-收口-2026-08-09/`；
  `web/` 旧静态壳标注废弃（`web/DEPRECATED_LEGACY_UI.md`）。详见 CHANGELOG 2026-08-09 条目。
  **剩余**：`ios-app/` 半成品原生 App 尚未取舍（见下条）。
- [~] **iOS 原生 App 取舍**（半办）：`build.yml` 产 unsigned IPA，无 Apple 开发者账号 + 签名
  无法分发。当前实际路线是 PWA。**2026-08-19 已停白烧**：`build.yml` 触发器去掉 `push: main`、
  只留 `workflow_dispatch`，不再每次 push 都白跑 macOS 构建烧 Actions 额度（保留按需 Run 能力，
  未删工作流可回退）。**仍待权哥拍板**：native 那套是补齐签名分发，还是彻底砍掉。
- [x] **回复截断** —— ✅ 已解决（2026-08-17 复核）：`max_tokens` 早已提到 2048（上限 4096），
  仅摘要类内部调用刻意用 300。长代码回复不再被截断。
- [x] **错误信息收敛** —— ✅ 复核后销案（2026-08-19）：真实**公开**泄露面已封住——最外层
  `fetch` catch 已 owner-gate（非主人只回错误编号 `errId`，原文仅回持 `OWNER_TOKEN` 的主人）；
  疑似泄露点如 `/cf-ai` 的 `ai_failed detail` 在路由处即强制 `OWNER_TOKEN`（属主人专属，非公开）。
  残留 `.message` 多为内部方法返回或主人专属操作，且已 `.slice()` 截断。判定：不值得为一个
  已基本非问题的项在 587KB 核心大文件上散点动刀,维持现状。
- [ ] **单一静态令牌**：无轮换 / 无过期 / 无多设备区分，按需升级。

---

## 🔵 P3 — 仅当做「产品版」才需要

- [ ] **多租户重构**：单 DO → 每用户独立 DO（`idFromName(userId)`），每用户独立灵魂 /
  配置 / 记忆 / 订阅。
- [ ] **注册 / 登录 / 账号体系**，替代单一 `OWNER_TOKEN`。
- [ ] **计费与用量隔离**，防止单用户拖垮共享算力配额。
- [ ] **`server/` 核心卖点接线**（省 Key 自适应推理 / 自进化 / 首次认识你 / 多智能体），
  详见 `CLOSURE_PLAN.md`——目前完整实现但全部未接线。

---

## 部署前手动核对

```bash
cd web/nexus-do
npm install && npm run build && node selftest.mjs   # 构建 + 自测
npx wrangler secret put OWNER_TOKEN                  # ★ 必设，否则安全闸会让部署失败
# 可选：主动推送 / 外接强算力大脑
npx wrangler secret put TG_BOT_TOKEN
npx wrangler secret put TG_QUAN_CHAT_ID
npx wrangler deploy
curl -s https://nexus-do.jjiebbay.workers.dev/health # 应返回 "secure":true
```
