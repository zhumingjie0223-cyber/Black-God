# Black God · 上线就绪清单（LAUNCH_CHECKLIST）

> 审计日期：2026-07-04（2026-07-06 补充：新增能力/接口的鉴权检查项）
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

- [ ] **限流 / 配额**：`/talk`（每条消息调 `callBrain` 两遍：回复 + 内心独白）、
  `/image` `/voice`（烧 CF AI）目前**零限流**。令牌泄露 = 无上限账单。
  加每分钟 / 每日调用上限。
- [ ] **前端别再静默假装在线**：`index.html` 所有请求 `catch → Demo.*` 会在后端挂掉时
  显示本地假数据。区分「离线 / 出错」与「正常」，给真实故障提示。
- [x] **隐私合规（基础版已加）**：新增 `/privacy` 公开只读页面（`PRIVACY_HTML`，说明
  访客/主人两类身份各采集什么、分享给谁、保留多久、怎么删除），落地页新增「隐私政策 /
  删除我的数据」链接；新增 `POST /unregister` 自助删除端点，访客凭自己的 `uid` 可随时
  清空注册记录。**上架前仍需你手动做**：
  - [ ] 把 `PRIVACY_HTML` 里的联系邮箱占位符换成真实可用邮箱（`web/nexus-do/nexus_do.core.mjs` 搜 `在此处填写你的联系邮箱`）
  - [ ] 视商店要求补充英文版隐私政策（Google Play 若面向多语言用户会要求）
  - [ ] 模拟亲密伴侣人格上架敏感，部分商店可能按「情感陪伴类」App 加审——先看目标商店的分类政策，必要时在商店后台的内容分级里如实申报
  - [ ] 若正式面向未成年人可及的公开商店，需评估是否要加年龄确认
- [ ] **端到端 / 鉴权回归测试**：目前只有 10 条纯逻辑自测；补路由、401、迁移、推送
  的集成测试。

---

## 🟡 P2 — 打磨 / 收尾

- [x] **部署去重（现状更新）**：root `wrangler.jsonc` 后来（PR #20）又被有意加回来了 ——
  `blackgod88` 这个 Worker 现在**故意**保留，专门发布旧静态首页 `web/index.html` 等文件；
  真正的产品 `nexus-do`（DO 大脑）与 `nexus-studio`（自主智能体工作台）各自有独立
  `wrangler.jsonc`，各走各的 GitHub Actions 部署，互不影响。
  之前的风险是 `blackgod88` 把整个 `web/` 目录当静态资源发布，会连
  `web/nexus-do/`、`web/nexus-studio/` 下的源码（`nexus_do.core.mjs`、`wrangler.jsonc`
  含 account_id 等）一起当裸文件公开发布——**已修复**：新增 `web/.assetsignore`
  排除这两个子目录，`blackgod88` 现在只发布真正的旧首页素材。
  另外发现 `web/nexus-do/studio.html` 与线上实际服务的 `web/nexus-studio/public/index.html`
  逐字节相同（前者是构建时未清理的重复文件，未被任何路由/构建脚本引用）——已删除。
- [ ] **`web/` 旧静态首页去留未定**：`web/index.html` 等文件是否还要保留对外可访问
  （`blackgod88` 域名），还是彻底下线改为只用 `aquan.lufei.uk`（`nexus-do`）当唯一入口，
  需要你确认后再决定是否删除文件 + 关闭 `blackgod88` 的 Cloudflare Git 集成
  （Workers → blackgod88 → Settings → Builds → 断开 Git）。
- [ ] **`server/`（Python 内核）去留未定**：有自己的 `Dockerfile`/`docker-compose.yml`
  可独立自托管跑，但其独有能力（省 Key 自适应推理/自进化/首次认识你/多智能体）尚未接入
  `nexus-do` 线上产品，见 `CLOSURE_PLAN.md`。是继续维护 Docker 自托管路线，还是把能力
  移植进 `nexus-do` 后归档，需要你决定。
- [x] **iOS 原生 App 取舍（先止损）**：无 Apple 开发者账号，`build.yml` 产的 unsigned
  IPA 签不了名、发不出去。已把 `build.yml` 触发方式从「每次 push 到 main 自动跑」改成
  仅 `workflow_dispatch`（手动触发），省 Actions 分钟数；`ios-app/` 代码本身还留着，
  等有开发者账号或决定彻底放弃原生 App 时再决定删不删。
- [ ] **回复截断**：`callBrain` 的 `max_tokens: 320` 会截断长代码类回复，按需调大。
- [ ] **错误信息收敛**：catch 把 `e.message` 直接回前端，轻微信息泄露。
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
