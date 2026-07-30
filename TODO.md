# TODO — 修复 Telegram 入站：让神枢能回主人的消息（权哥截图报障）

现象：Telegram「路飞技术服务」机器人能主动 push（08:38→13:59 一串），但权哥回她
「你为什么不跟我沟通」没任何回应。根因：**出站通、入站断**——Worker 只有 sendToQuan
出站，没有接收 Telegram 回调的 webhook 路由，她根本收不到主人在 TG 里说的话。

- [x] 定位根因：全路由表核对，确认无任何 Telegram 入站 webhook（只有 sendToQuan 出站）
- [x] 加入站路由 `POST /tg/webhook`（公开入口，不进 OWNER_TOKEN 门）+ `handleTgWebhook`
      · 双闸自保：setWebhook 密钥(X-Telegram-Bot-Api-Secret-Token) + 主人 chat_id 白名单
      · 幂等去重(update_id)、非文字提示、回话截断 3900、任何情况回 200 防重投
      · 喂进 `handleTalk`（与 /talk 同路，主人全功能），回话经 sendToQuan 发回 TG
- [x] 加 `POST /tg/setup`（系统主人专属）+ `tgSetWebhook`：一键把 webhook 注册到本 Worker
- [x] 自愈注册 `ensureTgHook`：心跳时用「记下的真实公网地址」自动注册，主人配好密钥+部署即自通
      （避开 cron 的 https://internal 伪地址：只认真实 web 访问记下的 origin）
- [x] 安全归位：`/tg/setup` 纳入 SYSTEM_ONLY_PATHS（多租户实例主人不可注册系统机器人）+ 私密集合
- [x] 测试：新增 tg_webhook.test.mjs 10/10（密钥/主人/幂等/非文字/截断/自愈注册）；
      selftest 228/0、capsec 39/0 全绿；index.html 未动（纯后端修复）
- [ ] 提交推送到分支
- [ ] 告诉权哥要生效需做的一步：Cloudflare 配 `TG_WEBHOOK_SECRET` 密钥 + 部署，之后自动接通

## 红线
- 入站是公开 HTTP 口，但双闸（密钥+主人 chat_id）把它牢牢锁死在主人本人；密钥未配则整条拒收，
  绝不留无鉴权入口通进主人大脑。危险动作仍走大脑内既有 need_confirm/授权闸，本入口不放行执行。
- 未碰词根表/编码/76.7 亿；未碰服务器/部署（代码落分支，部署由权哥侧走）。
