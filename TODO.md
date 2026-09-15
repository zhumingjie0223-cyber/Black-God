# 对照 OpenCode 直连配置 vs Cursor

- [x] 1.1 用权哥这份 OpenCode 基址+钥匙实测 gpt-6-astra — 直连 200，回「通」；`gpt-6` 别名 404 不支持
- [x] 1.2 对照本机 Cursor — 仍被盖成 `https://apiclaude.cc/v1`，composer=`default`；钥匙与 OpenCode 同款 sk- 已在 env
- [x] 1.3 说明：OpenCode 走 chat 直连即可；Cursor Agent 协议不同，照抄直连会踩注册表路由错，必须走协议桥隧道
- [x] 1.4 修好 Cursor 需权哥 Cmd+Q；密钥已出现在对话里，建议网关侧轮换

## 总结

OpenCode 这份配置对 `gpt-6-astra` 可用，但别用 `gpt-6`。Cursor 不能照抄 `baseURL: apiclaude.cc`，要走隧道协议桥；开着 Cursor 写库会被盖掉。
