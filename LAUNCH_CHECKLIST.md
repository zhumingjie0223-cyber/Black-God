# Black God · 上线就绪清单（LAUNCH_CHECKLIST）

> 审计日期：2026-07-04
> 上线主体：`web/nexus-do/`（Cloudflare Workers Durable Object，域名 `aquan.lufei.uk`）
> 结论：**私人版修完 P0 即可安心上线；面向客户则需多租户重构。**

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

## 🟠 P1 — 上线前应做（会出事 / 烧钱）

- [ ] **限流 / 配额**：`/talk`（每条消息调 `callBrain` 两遍：回复 + 内心独白）、
  `/image` `/voice`（烧 CF AI）目前**零限流**。令牌泄露 = 无上限账单。
  加每分钟 / 每日调用上限。
- [ ] **前端别再静默假装在线**：`index.html` 所有请求 `catch → Demo.*` 会在后端挂掉时
  显示本地假数据。区分「离线 / 出错」与「正常」，给真实故障提示。
- [ ] **隐私合规**（面向公众 / 上架必须）：`readRequestDevice` / `recordDevice` 采集
  IP、精确经纬度、运营商、设备型号、时区、电量并落库。需要隐私政策、采集同意、
  数据删除入口。模拟亲密伴侣人格上架敏感，先评估过审风险。
- [ ] **端到端 / 鉴权回归测试**：目前只有 10 条纯逻辑自测；补路由、401、迁移、推送
  的集成测试。

---

## 🟡 P2 — 打磨 / 收尾

- [x] **部署去重（已办一半）**：删掉了 root `wrangler.jsonc` —— 它把旧静态 `web/`
  站当资源部署成另一个 worker `blackgod88`，和真正的产品 `nexus-do` 并行跑。
  **仍需在 Cloudflare 面板手动关掉 `blackgod88` 的 Git 集成**（Workers → blackgod88 →
  Settings → Builds → 断开 Git），否则每次 push 那条 Workers Build 会因找不到配置而变红。
- [ ] **挑定唯一前门 / 归档旧壳**：`web/`（旧静态站，已弃用，改由 `web/nexus-do/` 内嵌
  UI 提供）、`server/`（Python 内核，孤儿未接线）、`ios-app/`（半成品原生 App）。
  确认 `nexus-do` 为唯一前门后，把 `web/` 旧静态文件与其余半成品归档。
- [ ] **iOS 原生 App 取舍**：`build.yml` 产 unsigned IPA，无 Apple 开发者账号 + 签名
  无法分发。当前实际路线是 PWA —— native 那套要么补齐要么砍掉（顺带停掉每次
  push 都跑的 macOS 构建，省 Actions 额度）。
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
