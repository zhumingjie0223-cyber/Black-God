# 神枢 App — 完整逆向工程报告

> 逆向日期: 2026-07-12
> 逆向环境: iOS 神枢 App, iSH Alpine Linux v3.21 aarch64
> 目标用途: 神枢 (Shuyu) 系统二次开发参考

---

## 一、物理架构

```
┌──────────────────────────────────────────────────────┐
│ iOS 神枢 App (Swift/ObjC)                           │
│ ├── DebugJSONRPC dispatcher                          │
│ ├── ModelRouter (Agent Loop + Provider management)   │
│ ├── SessionManager (CoreData/SQLite)                 │
│ ├── WKWebView (in-app browser)                       │
│ └── native_offload 桥接层 ←── 核心魔法               │
│     │                                                 │
│     │  拦截 0字节 stub 调用 → Swift 原生实现          │
│     │                                                 │
│ ┌───▼────────────────────────────────────────────┐   │
│ │ iSH Linux (Alpine v3.21, aarch64)              │   │
│ │ Kernel: Linux 4.20.69-ish SUPER AWESOME        │   │
│ │ Host: Apple Silicon (ARM64 native dispatch)     │   │
│ │ Rootfs: ~470GB available                       │   │
│ │                                                │   │
│ │ /var/shuyu/  会话文件系统 (fakefs)              │   │
│ │ ├── attachments/  上传的媒体文件                │   │
│ │ ├── browser/      浏览器截图+下载               │   │
│ │ ├── mcp-servers/  MCP配置+日志                  │   │
│ │ ├── memory/       每日日志+GLOBAL.md            │   │
│ │ ├── offloads/     大工具输出(>15k字符)          │   │
│ │ ├── shared/       跨会话持久存储                │   │
│ │ ├── skills/       技能定义(SKILL.md)            │   │
│ │ └── workspace/    工作文件                      │   │
│ └────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

---

## 二、native_offload 桥接机制（核心）

神枢 最精妙的设计：**0 字节桩文件 + 内核级拦截**。

### 2.1 桩文件列表

以下文件在 `/usr/local/bin/` 中均为 **0 字节空文件**，但被调用时有完整功能：

| 工具 | 功能 | 类别 |
|------|------|------|
| shuyu-config | 读写 App 配置（providers/models/groups） | 配置 |
| shuyu-model-use | 模型调用（Chat Completions API） | 模型 |
| shuyu-sessions-cli | 会话列表/搜索/消息/发送 | 会话 |
| shuyu-browser-use | 内置浏览器驱动 | 浏览器 |
| shuyu-debug | Debug JSONRPC（视图树/截图/日志） | 调试 |
| apple-healthkit | Apple Health 数据读写 | 系统 |
| apple-homekit | HomeKit 智能家居 | 系统 |
| apple-calendar | 日历读写 | 系统 |
| apple-reminders | 提醒事项 | 系统 |
| apple-vision | Vision 框架（OCR/分类/人脸/条码） | 系统 |
| apple-location | 定位 | 系统 |
| apple-maps | 地图搜索+路线 | 系统 |
| apple-photos | 相册 | 系统 |
| apple-clipboard | 剪贴板 | 系统 |
| apple-notification | 通知 | 系统 |
| apple-speak | TTS 语音合成 | 系统 |
| apple-speech | 语音识别 | 系统 |
| apple-player | 媒体播放 | 系统 |
| apple-alarm | 闹钟/计时器 | 系统 |
| apple-bluetooth | 蓝牙 | 系统 |
| apple-nfc | NFC | 系统 |
| apple-device | 设备信息 | 系统 |
| apple-weather | 天气 | 系统 |
| apple-open | 系统 URL 打开 | 系统 |

### 2.2 拦截流程

```
Shell 调用: shuyu-model-use run --model xxx
    ↓
exec() 系统调用
    ↓
iSH fakefs 检测到 0 字节文件
    ↓
native_offload 内核钩子触发
    ↓
dmesg: native_offload: [builtin] /usr/local/bin/shuyu-model-use (pid 877)
    ↓
路由到宿主 App 的 Swift 实现
    ↓
JSON 结果写回 stdout
    ↓
dmesg: native_offload: [builtin] /usr/local/bin/shuyu-model-use exited with code 0
```

### 2.3 真 Shell 脚本（2个）

只有两个工具是真正的 shell 脚本：

1. **shuyu-mcp-cli** (1267B) — MCP 客户端入口，确保 python3+httpx 后 exec Python
2. **shuyu-open** (3239B) — 发射 OSC 1337 转义序列通知宿主打开 URL/文件

---

## 三、MCP 子系统

### 3.1 架构

```
shuyu-mcp-cli (shell shim)
  └→ /usr/local/lib/shuyu-mcp-cli/
     ├── main.py      (18620 bytes)   CLI入口 + daemon 生命周期
     ├── daemon.py    (17394 bytes)   后台进程，10分TTL管理
     ├── transport/
     │   ├── __init__.py
     │   ├── http.py                  HTTP MCP transport
     │   └── stdio.py                 STDIO MCP transport
     └── utils/
         ├── __init__.py
         ├── config.py                servers.json 管理
         └── deps.py                  依赖检测
```

### 3.2 关键设计决策

- **IPC 走 127.0.0.1 TCP** — iSH 的 fakefs 不支持 AF_UNIX socket (bind→EPERM)
- **Daemon 冷启动锁** — `/tmp/shuyu-mcp-daemon.lock` 防 fork 风暴
- **端口发布** — `/tmp/shuyu-mcp-daemon.port` 写 ephemeral port
- **每 server 独立 10 分钟 TTL** — 空闲自动 kill
- **STDIO transport** — 直接持 `proc.stdin/stdout`，不落地 FIFO
- **RPC 超时 300s**，socket recv 超时 310s

### 3.3 当前连接的 MCP Server

```
vulneramcp:
  Transport: SSH + STDIO
  Host: aquan@35.241.124.34 (香港红队机)
  Command: node /opt/VulneraMCP/dist/index.js
  SSH Key: /var/shuyu/shared/credentials/gcp_key_new
  DB: PostgreSQL (bugbounty/bugbounty123)
  Redis: disabled
```

---

## 四、模型调用系统

### 4.1 Provider 配置（10个）

| Provider | 类型 | Base URL |
|----------|------|----------|
| Anthropic 3 | Anthropic OAuth | (原生) |
| Anthropic 2jie | Anthropic OAuth | (原生) |
| Claude-新加坡 | OpenAI | claude.lufei.uk |
| 网关 | Anthropic OAuth | claude.lufei.uk |
| DeepSeek | OpenAI | api.deepseek.com |
| 火山 | OpenAI | ark.cn-beijing.volces.com/api/coding/v3 |
| Minimax | OpenAI | api.minimaxi.com |
| Google Gemini | Gemini | (原生) |
| OpenAI 5 | OpenAI OAuth | (原生) |
| OpenAI Project Key (GOT) | OpenAI | (原生) |

### 4.2 Agent Loop（当前生效）

```
模型池: 3 个 (Anthropic 3 only)
  - claude-fable-5  (context: 1M tokens)
  - claude-opus-4-8  (context: 1M tokens)
  - claude-sonnet-5  (context: 1M tokens)

思考等级: xhigh
Max Output: 1,000,000 tokens (Fable/Sonnet/Opus)
```

### 4.3 调用链路

```
AI System Prompt → Agent Loop 选模型 → shuyu-model-use → native_offload
→ Swift ModelRouter → Provider API → 流式 SSE → 回显
```

---

## 五、环境变量

```
BROWSER=/usr/local/bin/shuyu-open      ← URL 拦截
GODEBUG=asyncpreemptoff=1              ← Go runtime 适配
GOMAXPROCS=2                            ← 资源限制
UV_THREADPOOL_SIZE=1                    ← libuv 限制
PYTHONDONTWRITEBYTECODE=1               ← 不写 .pyc
PYTHONMALLOC=malloc                     ← 用系统 malloc
NO_COLOR=1                              ← 禁用 ANSI
OPENSSL_armcap=0                        ← ARM 特性禁用
PIP_PROGRESS_BAR=off                    ← pip 静默
LANG=C.UTF-8
TZ=LCL-7
```

---

## 六、会话与会话文件系统

### 6.1 会话标识

- Session ID: UUID 格式 (如 `CF7F1DBD-EBE2-456E-A02E-6AB396129DD7`)
- 存储: CoreData/SQLite（宿主 App 层）
- 标题自动生成 (首尾消息对 → 子模型 → 统一推理参数)

### 6.2 文件系统布局

| 路径 | 用途 | 持久性 |
|------|------|--------|
| /var/shuyu/workspace/ | 工作文件 | 会话级 |
| /var/shuyu/attachments/ | 上传媒体 | 会话级 |
| /var/shuyu/browser/ | 浏览器输出 | 会话级 |
| /var/shuyu/offloads/ | 大输出(>15k) | 会话级 |
| /var/shuyu/shared/ | 跨会话共享 | 永久 |
| /var/shuyu/skills/ | 技能定义 | 永久(可导入) |
| /var/shuyu/memory/ | 日志+GLOBAL.md | 永久 |
| /var/shuyu/mcp-servers/ | MCP配置 | 永久 |
| /var/shuyu/mounts/ | 外部挂载(iOS Files) | 按挂载 |

### 6.3 shuyu:// URL 协议

```
shuyu://attachments/file.png   → /var/shuyu/attachments/file.png
shuyu://workspace/data.csv     → /var/shuyu/workspace/data.csv
shuyu://shared/project/f.txt   → /var/shuyu/shared/project/f.txt
shuyu://browser/screenshot.jpg → /var/shuyu/browser/screenshot.jpg
shuyu://offloads/output.txt    → /var/shuyu/offloads/output.txt
```

---

## 七、技能系统

### 7.1 格式

每个技能 = 一个目录，包含：
- `SKILL.md` — YAML frontmatter + Markdown 指令
- `scripts/` — 可执行脚本（可选）
- `pyproject.toml` — Python 依赖声明（可选）

### 7.2 SKILL.md 结构

```yaml
---
name: skill-name
description: 技能描述
priority: 950                    # 触发优先级
triggers: ["关键词1", "关键词2"]  # 自动触发词
compatibility: Requires xxx      # 依赖声明
---
## 目标
## 约束
## 命令清单
```

### 7.3 当前已装技能

| 技能 | 用途 |
|------|------|
| loan-hunter | 贷款获客全链路 |
| redteam-techniques | 红队渗透技术 |
| python-toolkit | Python 开发工具链 |
| skill-creator | 技能创建向导 |
| monid | 外部服务发现 |
| memory-keeper | 跨会话记忆管理 |

---

## 八、神枢集成路线图

### 立即可用（MIT/CC0，无风险）

1. **MinisSkills 44 个技能** → 神枢技能层
2. **MCP 子系统** → 神枢工具扩展框架
3. **shuyu-open OSC 1337 协议** → 神枢 URL 路由
4. **会话文件系统布局** → 神枢存储层

### 需要 GPL 兼容（ish-arm64/proot）

5. **ish-arm64** → 神枢 iOS 端 Linux 运行时
6. **proot** → 神枢 Android 端 Linux 运行时

### 需自行实现（未开源）

7. **native_offload 桥接层** — 0字节桩 + 内核拦截
8. **ModelRouter** — 多 Provider 调度
9. **Agent Loop** — 多模型轮转 + 故障转移
10. **SessionManager** — CoreData/SQLite 会话管理

---

## 九、附：文件清单

```
shuyu-reverse/
├── ARCHITECTURE.md              ← 本文档
├── mcp-cli/
│   ├── main.py                  MCP CLI 入口
│   ├── daemon.py                MCP 后台守护
│   ├── transport/
│   │   ├── __init__.py
│   │   ├── http.py              HTTP transport
│   │   └── stdio.py             STDIO transport
│   └── utils/
│       ├── __init__.py
│       ├── config.py            servers.json 管理
│       └── deps.py              依赖检测
├── shell/
│   ├── shuyu-open               OSC 1337 发射器
│   └── shuyu-mcp-cli            MCP CLI shim
├── skills/                      6 个已装技能 SKILL.md
├── configs/
│   ├── servers.json             MCP 服务器配置
│   ├── GLOBAL.md                全局记忆
│   ├── env_vars.txt             环境变量
│   ├── kernel_info.txt          内核信息
│   ├── os_release.txt           OS 版本
│   └── native_offload_patterns.txt  桥接模式日志
└── tools.txt                    28 个工具清单
```
