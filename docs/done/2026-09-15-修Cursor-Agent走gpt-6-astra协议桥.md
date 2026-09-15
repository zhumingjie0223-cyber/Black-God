# 修 Cursor Agent 调不通 gpt-6-astra

- [x] 1.1 查本机模型表：自定义 `gpt-6-astra` 被 Cursor 云端按错误协议路由
- [x] 1.2 直连网关：chat 与 responses 都能通；问题在 Cursor Agent 协议错位
- [x] 1.3 落地协议桥 + Cloudflare 公网隧道；修了桥把地址拼成 `/v1/v1` 的 bug；守护进程已装
- [x] 1.4 Cursor 已指向隧道地址，模型默认 `gpt-6-astra`；本地经隧道实测 Agent 形状请求返回 200

总结：以前报 400 是 Cursor Agent 协议和直连网关对不上。现已用本机协议桥把请求转成网关能吃的格式，再经公网隧道给 Cursor 云端打。权哥开新对话选 `gpt-6-astra`。
