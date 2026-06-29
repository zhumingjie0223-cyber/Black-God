# Black God · 真·Web Push（整合版 v3.2，iOS 加固）

> 一整版、可直接落进仓库。目标：**App 完全关闭也能收推送**，iOS 上稳。
> 开源友好，零付费依赖：用浏览器原生 Push API + VAPID，自己的服务器自己推。

## 先破一个误区

**iOS 上不需要让 App「挂后台保活」。** 真·Web Push 是苹果推送服务（`web.push.apple.com`）替你送达并唤醒 Service Worker，App 可以被彻底杀掉。要"稳"，靠的是下面三条，已在代码里做硬：

1. **每次 push 必弹通知**——`sw.js` 的 `push` 处理里，无论 payload 空/坏都强制 `showNotification`。iOS 一旦发现你"静默推送"会逐步收回推送配额，从此收不到，这是最大的坑。
2. **订阅自动续**——系统轮换订阅时 `pushsubscriptionchange` 自动重订；每次打开 App 还有 `autoResync` 兜底补订阅。
3. **必须装到主屏幕**——iOS 只允许「添加到主屏幕」的 PWA 推送。`push-client.js` 会检测，没装就提示用户去添加。

## 目录结构

```
blackgod-webpush/
├── install.sh                 # 一键拷进仓库 + git commit（不 push）
├── README_WEBPUSH.md
├── .gitignore                 # 已排除私钥/订阅库
├── web/
│   ├── index.html             # 已接好线（开关/引导/通知点击跳转/iOS 提示）
│   ├── sw.js                  # v3.2 iOS 加固：push 永远弹通知
│   ├── push-client.js         # iOS 感知订阅助手 window.BGPush
│   ├── manifest.json
│   ├── icon-192.png / icon-512.png
└── server/
    ├── server_push_example.py # 推送后端：订阅存储 + 发送（TTL/限流/失效清理）
    ├── server_sse_example.py  # 你的 SSE 后端，已接入 push_to_user
    ├── requirements.txt       # pywebpush
    └── vapid_private.pem      # 私钥（被 .gitignore 排除，不提交）
```

## 落地（两种方式）

### A. 一键脚本（推荐）
```bash
cd /你的/blackgod          # 已 clone 的仓库根目录
bash /解压目录/blackgod-webpush/install.sh
git push origin main       # 用你的新 token，别写进 URL
```

### B. 手动
把 `web/` 与 `server/` 对应拷过去，确认 `.gitignore` 含 `server/vapid_private.pem`，再 commit。

## 跑起来 & 自测

```bash
# 前端（本地 localhost 被当作安全上下文，可直接测）
cd web && python3 -m http.server 8765

# 后端
cd server && pip install -r requirements.txt
python3 server_push_example.py        # :8766
# 把 server_push_example.py 里 VAPID_CLAIMS 的 mailto 改成你的邮箱
```

**验证「全关也能收」：**
1. 前端开「任务通知」，控制台出现 `[BGPush] 已订阅 ...`
2. 彻底关掉 App（PWA 划掉 / 浏览器退出）
3. `curl -X POST http://127.0.0.1:8766/api/push/test -H 'Content-Type: application/json' -d '{"title":"全关测试 ✓","body":"看到我就成了"}'`
4. 锁屏/通知栏出现 → 点它自动打开 App ✓

**iOS 真机验证：** 必须 iOS 16.4+，Safari 打开你的线上 HTTPS 站 → 分享 ⬆️ →「添加到主屏幕」→ 从主屏幕图标打开 → 开通知 → 杀掉 App → 后端 `test` → 锁屏应收到。

## 接到你的 Agent
`server_sse_example.py` 已在任务 `done`（完成/失败）和危险操作 `confirm` 时调用 `push_to_user(...)`。
`user_id` 取前端 `userProfile.id/name`，要和前端 `BGPush` 上报的一致才能"只推给本人"。

## 上生产必做（示例没做）

- **订阅存储换数据库**：`subscriptions.json` 只够 demo，多进程会打架。换 Redis/SQLite/Postgres，按 `userId` 建索引。
- **接口鉴权**：`/api/push/*` 现在裸奔，`/api/push/test` 上线务必关掉或加管理员鉴权。
- **HTTPS 必备**：除 localhost 外不给推送。
- **密钥保密**：`vapid_private.pem` 泄露＝别人能冒充你向你的用户推送。已加 `.gitignore`，别手贱提交。
- **频控**：只在"完成/失败/需确认"等节点推，别把每个 token 事件都推。

## 换 VAPID 密钥（可选）

我给的密钥可直接用。要换成你自己的：
```bash
pip install py-vapid && vapid --gen     # 或用 web-push generate-vapid-keys
```
拿到公钥后，**三处一起改**：`web/sw.js`、`web/push-client.js`、`server/server_push_example.py` 里的 `VAPID_PUBLIC_KEY`；私钥替换 `vapid_private.pem`。换完老订阅作废，用户下次打开会自动重订。

## 常见坑速查

| 现象 | 原因 |
|---|---|
| 完全不弹 | 没 HTTPS / 权限非 granted / `sw.js` 没更新（DevTools→Application→SW 点 Update） |
| iOS 收不到 | 没「添加到主屏幕」/ 系统 <16.4 |
| 几条后突然收不到了 | 后端发过"无通知的静默推送"被 iOS 惩罚——本版已强制每次弹，避免此问题 |
| 收到的通知是空的 | 后端 `data=` 必须是字符串（已用 json.dumps）；SW 已兜底 |
| 换公钥后全员收不到 | 三处没同步改，或老订阅没重订 |
