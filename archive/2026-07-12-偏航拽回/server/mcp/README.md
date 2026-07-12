# 神枢 MCP 子系统 — Minis MCP 源码集成

## 来源
Minis App (iOS/Android) — APK assets/default_mount/usr/local/lib/minis-mcp-cli/
逆向日期: 2026-07-12
通过 APK 解包直接提取完整 Python 源码

## 架构

```
shuyu-mcp-cli (shell shim)
  └→ server/mcp/
     ├── main.py       (18.6KB) CLI入口 + daemon生命周期
     ├── daemon.py     (17.4KB) TCP IPC后台 + MCP连接池(10分钟TTL)
     ├── transport/
     │   ├── http.py   (6.0KB)  HTTP SSE transport
     │   └── stdio.py  (5.3KB)  STDIO 子进程管道
     └── utils/
         ├── config.py (2.9KB)  servers.json 管理
         └── deps.py   (2.5KB)  依赖检测

shuyu-mcp-cli — Python环境自举shell shim
shuyu-open     — OSC 1337转义序列,宿主App URL路由
```

## 关键设计

- IPC: 127.0.0.1 TCP (非AF_UNIX, iSH fakefs限制)
- 每server独立10分钟空闲TTL
- RPC超时300s, socket超时310s
- servers.json兼容Claude Desktop格式
