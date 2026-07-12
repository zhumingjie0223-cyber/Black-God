# 神枢 完整逆向规格书 — 神枢重建蓝图

> 逆向日期: 2026-07-12 | 版本: v3.0-final
> 数据源: 实时系统逆向 + GitHub 7仓库 + 19发行版 + 22 Issues + 6技能库
> 目标: 为神枢(Shuyu)系统提供可重实现的完整接口规格

---

## 目录

1. [总体架构](#1-总体架构)
2. [native_offload 桥接层](#2-native_offload-桥接层)
3. [工具系统接口规格](#3-工具系统接口规格)
4. [模型调用系统](#4-模型调用系统)
5. [MCP 子系统](#5-mcp-子系统)
6. [浏览器子系统](#6-浏览器子系统)
7. [会话与会话文件系统](#7-会话与会话文件系统)
8. [技能系统](#8-技能系统)
9. [内存/记忆系统](#9-内存记忆系统)
10. [配置管理(shuyu-config)](#10-配置管理shuyu-config)
11. [调试系统(shuyu-debug)](#11-调试系统shuyu-debug)
12. [已知缺陷与规避](#12-已知缺陷与规避)
13. [神枢实现路线图](#13-神枢实现路线图)

---

## 1. 总体架构

```
┌──────────────────────────────────────────────────────────┐
│                  神枢 App (Swift/ObjC)                   │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ ModelRouter   │  │ SessionMgr   │  │ ToolDispatch  │   │
│  │ (Agent Loop)  │  │ (CoreData)   │  │ (JSONRPC)    │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
│         │                 │                 │            │
│  ┌──────▼─────────────────▼─────────────────▼───────┐   │
│  │            native_offload 桥接层                  │   │
│  │   0字节桩拦截 → Swift原生实现 → JSON stdout       │   │
│  └──────────────────────┬───────────────────────────┘   │
│                         │                                │
│  ┌──────────────────────▼───────────────────────────┐   │
│  │        iSH Linux (Alpine v3.21, aarch64)         │   │
│  │  Kernel: 4.20.69-ish SUPER AWESOME               │   │
│  │  fs: fakefs (/var/shuyu/) + apk包管理             │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

### 1.1 各层职责

| 层 | 技术 | 职责 |
|----|------|------|
| ModelRouter | Swift/Kotlin | Provider管理、Agent Loop轮转、模型切换、故障转移 |
| SessionManager | CoreData(Swift)/Room(Android) | 会话CRUD、消息存储、标题生成 |
| ToolDispatch | JSONRPC Dispatcher | 工具路由、参数校验、超时管理 |
| native_offload | iSH内核钩子 | 拦截0字节桩→宿主App原生实现 |
| iSH Linux | C/asm | x86/ARM64模拟、syscall翻译、fakefs |

---

## 2. native_offload 桥接层

### 2.1 原理

神枢 在 `/usr/local/bin/` 放置 0 字节桩文件。当 iSH 内的 shell 进程 `exec()` 这些文件时，iSH 内核的 `native_offload` 钩子拦截调用，不执行文件内容（本来就是空的），而是将调用转发到宿主 App 的 Swift 原生实现。

### 2.2 调用流程

```
Shell: shuyu-config get providers
  → exec("/usr/local/bin/shuyu-config")
  → iSH kernel: 检测 0 字节文件
  → native_offload: [builtin] /usr/local/bin/shuyu-config (pid 877)
  → 参数通过某种 IPC 传到宿主 App
  → Swift 原生实现执行
  → JSON 结果写回 stdout
  → native_offload: exited with code 0
```

### 2.3 桩文件完整列表

#### 配置管理 (1个)
| 桩文件 | 功能 |
|--------|------|
| `shuyu-config` | 读写 App 配置（providers, models, model-groups, defaults, skills, envvars） |

#### 模型调用 (1个)
| 桩文件 | 功能 |
|--------|------|
| `shuyu-model-use` | 调用 LLM (Chat Completions + Image Generation + TTS) |

#### 会话管理 (1个)
| 桩文件 | 功能 |
|--------|------|
| `shuyu-sessions-cli` | 会话列表/搜索/消息读取/发送/重试/状态 |

#### 浏览器 (1个)
| 桩文件 | 功能 |
|--------|------|
| `shuyu-browser-use` | WKWebView 驱动 (navigate/screenshot/click/type/scroll/js) |

#### 调试 (1个)
| 桩文件 | 功能 |
|--------|------|
| `shuyu-debug` | DebugJSONRPC（视图树/截图/日志/文件读写/overlay） |

#### 系统集成 (21个 apple-* 桩)
| 桩文件 | iOS Framework | 功能 |
|--------|---------------|------|
| `apple-healthkit` | HealthKit | 健康数据读写（100+ 指标） |
| `apple-homekit` | HomeKit | 智能家居控制 |
| `apple-calendar` | EventKit | 日历读写 |
| `apple-reminders` | EventKit | 提醒事项 |
| `apple-vision` | Vision | OCR/分类/人脸/条码/图片相似度 |
| `apple-location` | CoreLocation | 定位 |
| `apple-maps` | MapKit | 搜索/路线/ETA |
| `apple-photos` | Photos | 相册读写 |
| `apple-clipboard` | UIKit | 剪贴板读写 |
| `apple-notification` | UserNotifications | 通知推送 |
| `apple-speak` | AVFAudio | TTS 语音合成 |
| `apple-speech` | Speech | 语音识别 |
| `apple-player` | AVFoundation | 媒体播放(pause/resume/seek/status) |
| `apple-alarm` | AlarmKit | 闹钟/计时器(iOS 26+) |
| `apple-bluetooth` | CoreBluetooth | 蓝牙扫描 |
| `apple-nfc` | CoreNFC | NFC 读写 |
| `apple-device` | UIKit | 设备信息(电池/型号) |
| `apple-weather` | WeatherKit | 天气 |
| `apple-open` | UIKit | 系统 URL handler (tel:/mailto:/maps://等) |
| `apple-media` | MediaPlayer | 媒体库 |
| `apple-nlp` | NaturalLanguage | 自然语言处理 |

### 2.4 真脚本 (非桩, 2个)

| 脚本 | 语言 | 原理 |
|------|------|------|
| `shuyu-mcp-cli` | Shell→Python | 确保 python3+httpx, exec Python |
| `shuyu-open` | Shell | 发射 OSC 1337 转义序列 |

### 2.5 神枢实现建议

神枢可以复用同一套桩文件机制——在 ish-arm64 的 fakefs 中注册相同的 0 字节文件，然后实现自己的 native_offload handler。桩文件的名称和命令行接口保持兼容即可。

---

## 3. 工具系统接口规格

### 3.1 工具调用协议

所有工具遵循统一的 JSON 输入/输出协议：

**输入**: 命令行参数 (key=value 或 JSON)
**输出**: JSON envelope `{"ok": true/false, "data": {...}, "error": {...}, "timestamp": "..."}`

### 3.2 通用选项

| 选项 | 说明 |
|------|------|
| `--help` | 显示帮助 |
| `--compact` | 压缩 JSON 输出 |
| `-q, --quiet` | 仅输出 data 字段 |

### 3.3 关键工具的子命令/接口

#### shuyu-config

```
get <path>         读取配置 (支持 --filter --page --page-size)
set <path> <value> 写入配置 (触发 30 秒确认弹窗)
topic-help <topic> 查看某话题的字段列表
```

**已知路径**:
- `providers` — LLM provider 列表
- `providers.<id>.apiKey` — provider API key (只写)
- `providers.<id>.isEnabled` — 启用/禁用
- `models` — 所有模型条目
- `models.<entry_id>.isHidden` — 隐藏模型
- `models.<entry_id>.maxOutputTokens` — 最大输出 token
- `models.<entry_id>.modalitiesOverride` — 模态覆盖
- `models.<entry_id>.contextWindowOverride` — 上下文窗口覆盖
- `defaults.agentLoopEntries` — Agent Loop 模型池 (string 数组)
- `defaults.defaultThinkingLevel` — 默认思考等级
- `envvars` — 环境变量列表
- `skills` — 技能列表

#### shuyu-model-use

```
list                          列出可用模型 (来自 agentLoopEntries)
run --model <id> [--input <json_file>]
    [--provider <label>]      调用模型
```

**输入 JSON 格式** (Chat Completions):
```json
{
  "messages": [
    {"role": "user", "content": "text"}
  ],
  "generation_config": {
    "size": "1024x1024",
    "n": 1,
    "quality": "standard"
  }
}
```

**已知缺陷** (从 Issues):
- `tools`/`plugins`/`web_search_options` 字段静默丢弃 (#72)
- `input_audio` content block 静默丢弃 (#67)
- `images_generations` 端点丢弃非白名单字段 (#62)
- Tool calling 参数序列化为空对象 (#61)
- Anthropic 协议 thinking mode 多轮 tool call 后报错 (#70)

#### shuyu-sessions-cli

```
list [--start YYYY-MM-DD] [--end YYYY-MM-DD] [--limit N]
search --keywords <words> [--ids ...]
messages --id <session_id> [--offset N] [--limit N] [--full]
send <prompt> [--session <id>] [--attach <path>] [--model <entry_id>]
retry --session <id> [--message <msg_id>]
status --id <session_id>
open <session_id>
```

#### shuyu-browser-use

```
navigate --url <url>
screenshot [--full-page] [--with-base64]
click --selector <css> | --coordinate-x N --coordinate-y N
type --selector <css> --text <text>
get_text --selector <css>
scroll [--selector <css>] [--direction up|down] [--amount PX]
execute_js --script <js>
find_elements --selector <css>
hover --selector <css>
get_readable
get_page_info
get_backbone [--max-depth N]
fetch --url <url>
get_cookies [--keywords <list>] [--fuzzy]
scroll_and_collect --scroll-count N [--item-selector <css>]
wait_for_dom_stable [--timeout MS]
set_user_agent --user-agent mobile_safari|desktop_safari
set_viewport --width N --height N | --reset
new_tab [--url <url>]
close_tab [--tab-id N]
list_tabs
```

**输出** (screenshot):
```json
{
  "data": {
    "text": "Screenshot captured",
    "success": true,
    "page_url": "https://...",
    "image_path": "/var/shuyu/browser/screenshot_<ms>.jpg",
    "shuyu_url": "shuyu://browser/screenshot_<ms>.jpg"
  }
}
```

#### shuyu-debug

```
discover                     列出所有 JSONRPC 方法
viewTree [--maxDepth N]      视图层级树
search <keyword> [...]       搜索视图
inspect <address>            检查视图
highlight <address> [--color] [--duration]  高亮视图
trace [--last]               智能体追踪记录
ls [path] [--recursive]      列出沙盒文件
read <path> [--offset] [--limit] [--base64]  读沙盒文件
write <path> --content <text> [...]          写沙盒文件
exec <command...>            执行 shell 命令(via DebugServer)
screenshot [--scale N]       宿主级截图(PNG base64)
snapshot <list|get|clear|...> 内存快照管理
overlay <enable|disable|mode> 调试 overlay 层
logs [--last N] [--minutes N] [--grep K]    App 运行时日志
```

---

## 4. 模型调用系统

### 4.1 Provider 类型与协议

神枢 支持 5 种 provider 类型:

| ProviderType | 协议 | 端点格式 |
|-------------|------|---------|
| `anthropic` | Anthropic Messages API | `/v1/messages` |
| `openAI` | OpenAI Chat Completions | `/v1/chat/completions` |
| `openAIResponses` | OpenAI Responses API | `/v1/responses` |
| `gemini` | Google Gemini API | `generativelanguage.googleapis.com` |
| `openRouter` | OpenRouter (OpenAI兼容) | `/api/v1/chat/completions` |

### 4.2 Provider 配置结构

```json
{
  "id": "UUID",
  "label": "显示名称",
  "providerType": "openAI|anthropic|gemini|openAIResponses|openRouter",
  "credentialType": "apiKey|oauth",
  "isEnabled": true,
  "customBaseURL": "https://...",
  "appendV1Suffix": true,
  "imageEndpointMode": "auto|separate|disabled"
}
```

### 4.3 模型条目结构

```json
{
  "entry_id": "providerUUID/model_id",
  "model_id": "claude-sonnet-5",
  "display_name": "Claude Sonnet 5",
  "provider_label": "Anthropic 3",
  "provider_type": "anthropic",
  "is_custom": false,
  "is_hidden": false,
  "modalities": ["text_input","text_output","image_input","pdf_input"],
  "supportsTools": true,
  "supportsVision": true,
  "contextWindow": 1000000,
  "maxOutputTokens": 1000000
}
```

### 4.4 Agent Loop 机制

```
defaults.agentLoopEntries: [
  "providerUUID/model_id",
  ...
]
```

- **故障转移**: 按顺序尝试，某个失败自动切换下一个
- **负载均衡**: 将对话均匀分配到各模型
- **当前缺陷**: Agent Loop 模型与全局模型目录分离——模型目录里有 60+ 模型，但 Agent Loop 只配置了 3 个

### 4.5 思考等级 (Thinking Level)

```
low → medium → high → xhigh
```

- 仅 Anthropic 协议和部分 OpenAI 兼容模型支持
- 深度思考模型 (如 Sonnet 5/Fable 5) 在 xhigh 下产生数万字推理
- UI 采用窗口化渲染（只渲染尾部 + 超大内容原生查看器）避免卡死 (#18 修复)

### 4.6 流式输出

- SSE (Server-Sent Events) 格式
- iOS 端: 文字逐词淡入、按"时间或换行"双策略分段刷新
- Android 端: 0.17-preview 对齐 iOS 体验

### 4.7 已知协议 Bug (神枢规避清单)

| Issue | 问题 | 规避方案 |
|-------|------|---------|
| #72 | web_search/tools/plugins 字段丢弃 | 神枢在 ModelRouter 中保留并透传这些字段 |
| #70 | Anthropic thinking 多轮 tool call 后报错 | 在 thinking block 回传逻辑中检查 content 数组完整性 |
| #67 | input_audio block 静默丢弃 | content 序列化时遍历所有 block 类型,不硬编码 |
| #62 | images_generations 非白名单字段丢弃 | 全字段透传,不做白名单过滤 |
| #61 | Tool calling 参数空对象 | 参数序列化前做 null check |
| #68 | 无法切换 Chat/Image API | Provider 级 imageEndpointMode 独立配置 |
| #59 | 英文自动换行打断单词 | 使用 CSS word-break 优化 |

---

## 5. MCP 子系统

### 5.1 完整源码结构

```
/usr/local/lib/shuyu-mcp-cli/
├── main.py         18620B   CLI + daemon 生命周期管理
├── daemon.py       17394B   TCP IPC 后台 + MCP 连接池
├── transport/
│   ├── __init__.py
│   ├── http.py      6010B   HTTP transport (SSE 流式)
│   └── stdio.py     5259B   STDIO transport (子进程管道)
└── utils/
    ├── __init__.py
    ├── config.py    2858B   servers.json CRUD
    └── deps.py      2470B   依赖检测 (command/python/pkg)
```

### 5.2 CLI 接口

```
shuyu-mcp-cli list [--all] [--pretty]
shuyu-mcp-cli tools <server> [--pretty]
shuyu-mcp-cli info <server> [--pretty]
shuyu-mcp-cli ping <server> [--pretty]
shuyu-mcp-cli call <server> <tool> [--input '{}'] [k=v ...]
shuyu-mcp-cli add --name N (--url U [--header "K: V"] | --command C [--args "..."] [--env "K=V"])
shuyu-mcp-cli remove <server>
shuyu-mcp-cli enable <server>
shuyu-mcp-cli disable <server>
shuyu-mcp-cli shutdown
```

### 5.3 Daemon 关键设计参数

| 参数 | 值 | 说明 |
|------|-----|------|
| TTL_SECONDS | 600 | 每 server 10 分钟空闲 TTL |
| WATCHDOG_INTERVAL | 30 | TTL 扫描间隔 |
| DAEMON_EXIT_GRACE | 60 | 空池后 60 秒退出 |
| RPC_TIMEOUT | 300.0 | 单次 RPC 超时 |
| CONN_TIMEOUT | 310.0 | Socket recv 超时 |
| LOCK_STALE_SECONDS | 12.0 | 冷启动锁过期时间 |

### 5.4 IPC 协议

- 传输: 127.0.0.1 TCP (非 AF_UNIX, 因为 iSH fakefs 不支持)
- 端口文件: `/tmp/shuyu-mcp-daemon.port`
- PID 文件: `/tmp/shuyu-mcp-daemon.pid`
- 锁文件: `/tmp/shuyu-mcp-daemon.lock`

Daemon 内部协议: JSON line-delimited, 每条消息以 `\n` 结尾:
```json
{"method": "tools/list", "id": 1}
{"method": "tools/call", "id": 2, "params": {"name": "tool_name", "arguments": {}}}
```

### 5.5 servers.json 格式 (Claude Desktop 兼容)

```json
{
  "mcpServers": {
    "server_name": {
      "command": "node",
      "args": ["/path/to/server.js"],
      "env": {"KEY": "value"},
      "enabled": true,
      "note": "description",
      "createdAt": 1234567890.0
    }
  }
}
```

HTTP 模式:
```json
{
  "mcpServers": {
    "server_name": {
      "url": "https://mcp.example.com/sse",
      "headers": {"Authorization": "Bearer xxx"},
      "enabled": true
    }
  }
}
```

### 5.6 神枢移植

MCP 子系统是 神枢 中最适合直接移植的部分:
- 纯 Python, 约 50KB 代码
- 只依赖 python3 + httpx
- 协议兼容 Claude Desktop 生态
- 移植时只需改 daemon 的 IPC (如果神枢支持 AF_UNIX)

---

## 6. 浏览器子系统

### 6.1 实现

- iOS: WKWebView, 内置在 神枢 App 中
- Android: WebView
- User-Agent: 默认 Safari Desktop
- Viewport: 可覆盖 (set_viewport)

### 6.2 关键特性

- 最多 3 个 tab 并行
- 支持 full-page 截图 (cap 32768px)
- `scroll_and_collect` 用于无限滚动页面 (Twitter/X)
- `get_backbone` 提供简化的 DOM 树
- `get_cookies` 返回 HttpOnly cookies (通过宿主原生 API)
- `fetch` 使用页面 session 下载文件

### 6.3 文件路径规范

| 类型 | 路径 |
|------|------|
| 截图 | `/var/shuyu/browser/screenshot_<timestamp>.jpg` |
| 下载 | `/var/shuyu/browser/<filename>` |
| minis URL | `shuyu://browser/<filename>` |

### 6.4 神枢实现

神枢可用 WebKit/WKWebView (iOS) 或 WebView (Android) 实现, 或使用 headless Chrome CDP 协议。

---

## 7. 会话与会话文件系统

### 7.1 会话模型

```
Session {
  session_id: UUID
  title: String (自动生成)
  started_at: DateTime
  last_active: DateTime
  message_count: Int
  preview: String (首条消息截断)
  messages: [Message]
  source: "chat" | "cli" | "scheduled"
}

Message {
  message_id: UUID
  role: "user" | "assistant" | "system" | "tool"
  content: String
  attachments: [Attachment]
  thinking: String? (深度思考内容)
  tool_calls: [ToolCall]?
  timestamp: DateTime
}
```

### 7.2 文件系统命名空间

| Namespace | 路径 | 持久性 | 用途 |
|-----------|------|--------|------|
| workspace | `/var/shuyu/workspace/` | 会话级 | 代码/数据/工作文件 |
| attachments | `/var/shuyu/attachments/` | 会话级 | 用户上传的媒体 |
| browser | `/var/shuyu/browser/` | 会话级 | 截图+下载 |
| offloads | `/var/shuyu/offloads/` | 会话级 | >15K 的大工具输出 |
| shared | `/var/shuyu/shared/` | 永久 | 跨会话共享 |
| skills | `/var/shuyu/skills/` | 永久 | SKILL.md 技能 |
| memory | `/var/shuyu/memory/` | 永久 | 每日日志+GLOBAL.md |
| mcp-servers | `/var/shuyu/mcp-servers/` | 永久 | MCP 配置+日志 |
| mounts | `/var/shuyu/mounts/<name>/` | 按挂载 | 外部目录(iOS Files) |

### 7.3 shuyu:// URL 协议

```
shuyu://attachments/file.png   → /var/shuyu/attachments/file.png
shuyu://workspace/data.csv     → /var/shuyu/workspace/data.csv
shuyu://shared/project/f.txt   → /var/shuyu/shared/project/f.txt
shuyu://browser/screenshot.jpg → /var/shuyu/browser/screenshot.jpg
shuyu://offloads/output.txt    → /var/shuyu/offloads/output.txt
```

宿主 App 解析 shuyu:// URL → 根据扩展名路由到对应查看器:
- 图片 → 原生图片查看器
- .md → Markdown 预览
- .html → HTML 预览
- .pdf/.docx → QuickLook
- 音频/视频 → 媒体播放器

### 7.4 OSC 1337 协议 (shuyu-open)

```
ESC ] 1337 ; MinisOpenURL = <url> BEL

ESC = 0x1B
BEL = 0x07
```

宿主 App 从 stdout 中剥离这些序列，路由 URL:
- `http://` `https://` → WKWebView
- `shuyu://` → 按扩展名路由
- `/var/shuyu/...` → 自动转换为 shuyu://

---

## 8. 技能系统

### 8.1 SKILL.md 格式

```yaml
---
name: skill-name
description: 描述
priority: 950
triggers: ["触发词1", "触发词2"]
compatibility: Requires python3, curl
---
## 目标
## 约束
## 命令清单
## 脚本入口
```

### 8.2 技能目录结构

```
skill-name/
├── SKILL.md          # 核心指令 (YAML frontmatter + Markdown)
├── scripts/          # 可执行脚本
│   └── run.sh
├── pyproject.toml    # Python 依赖声明
└── uv.lock           # 依赖锁文件
```

### 8.3 生命周期

1. 导入: URL 或文件系统 → 解析 SKILL.md → 注册到 `shuyu-config skills`
2. 触发: AI 检测到 trigger 词 → 加载 SKILL.md 内容到 system prompt → 执行
3. 禁用: 按会话禁用/启用
4. 卸载: 从 skills 目录删除

### 8.4 神枢集成

44 个 MinisSkills (MIT 许可) 可直接导入神枢。技能格式 (SKILL.md) 是纯 Markdown, 神枢可以:
- 直接复用 SKILL.md 作为神枢的"术"模块
- 迁移 scripts/ 中的 Python 脚本
- 扩展 triggers 机制适配神枢的语义空间

---

## 9. 内存/记忆系统

### 9.1 存储结构

```
/var/shuyu/memory/
├── GLOBAL.md          # 永久全局记忆 (用户维护)
├── YYYY-MM-DD.md      # 每日日志 (AI 自动写入)
```

### 9.2 GLOBAL.md

- 存储: 凭证、API Key、服务器配置、偏好
- 维护: 用户手动编辑 (read-only for AI)
- 注入: 每次会话开始时自动注入 system prompt

### 9.3 每日日志

- 格式: Markdown, 带时间戳的条目
- 写入: `memory_write` 工具
- 搜索: `memory_get` 工具 (关键词模糊搜索)

### 9.4 记忆工具接口

```
memory_write(content)  → 追加到今天的日志
memory_get(keywords)   → 搜索所有日志
```

---

## 10. 配置管理 (shuyu-config)

### 10.1 配置树

```
providers[]                         Provider 实例
  .label
  .providerType
  .credentialType
  .isEnabled
  .customBaseURL
  .apiKey (只写)
  .appendV1Suffix
  .imageEndpointMode

models.<provider_id>/<model_id>    模型条目
  .displayName
  .isHidden
  .maxOutputTokens
  .modalitiesOverride
  .contextWindowOverride

defaults
  .agentLoopEntries[]               Agent Loop 模型池
  .defaultThinkingLevel             思考等级

envvars[]                           环境变量
  .key
  .value (只写)
  .note

skills[]                            技能列表
  .name
  .path
  .enabled
```

### 10.2 写入确认机制

- 写操作触发 30 秒确认弹窗
- 超时 → `Confirmation timed out after 30s`
- 写入日志: 1000 条可回滚审计记录

---

## 11. 调试系统 (shuyu-debug)

### 11.1 JSONRPC 方法 (DebugServer)

已知方法 (从 --help 反推):
- `rpc.discover` — 列出所有方法
- `viewTree` — 视图层级
- `searchViews` — 搜索视图
- `inspectView` — 检查视图属性
- `highlightView` — 高亮覆盖层
- `trace.list` / `trace.get` — 智能体追踪
- `file.list` / `file.read` / `file.write` — 沙盒文件操作
- `shell.exec` — 通过 DebugServer 执行 shell
- `screenshot` — 宿主级截图
- `snapshot.*` — 内存快照
- `overlay.*` — 调试覆盖层
- `logs.query` — App 日志

### 11.2 日志系统

- 源: OSLogStore + LoggingManager
- 可在 Release build 中读取
- 支持: `--last N` `--minutes N` `--grep keyword`

---

## 12. 已知缺陷与规避

从 Issues + Release Notes + 实时系统观察到的缺陷汇总:

### 12.1 模型调用层

| ID | 缺陷 | 影响 | 神枢规避 |
|----|------|------|---------|
| #72 | web_search/tools/plugins 字段丢弃 | 无法使用原生搜索 | 全字段透传 |
| #70 | Anthropic thinking 多轮 tool call 竞态 | 20% 重试成功 | thinking block 数组完整性检查 |
| #67 | input_audio 静默丢弃 | 无法接入自定义 STT | 遍历所有 content block 类型 |
| #62 | images_generations 非白名单丢弃 | 图生图失败 | 白名单去掉,全透传 |
| #61 | Tool call 参数空对象 | 工具调用失败 | null check + schema 校验 |

### 12.2 Provider 层

| ID | 缺陷 | 神枢规避 |
|----|------|---------|
| #68 | Chat/Image API 无法切换 | Provider级独立 imageEndpointMode |
| #59 | 英文换行打断单词 | CSS word-break: keep-all |

### 12.3 系统层

| ID | 缺陷 | 神枢规避 |
|----|------|---------|
| #65 | iOS 后台驻留差 | 使用 BGTaskScheduler + 悬浮窗 |
| #64 | 强制引号字符转换 | 不转换,原样保留 |
| #63 | ish-bun-memfd-bug | 使用 Node.js 而非 Bun |

### 12.4 Agent Loop 层

| 观察 | 现状 | 神枢改进 |
|------|------|---------|
| Agent Loop 模型数 | 3 个 (Anthropic 3 only) | 支持多 provider 动态池 |
| 故障转移 | 顺序重试 | 增加熔断+退避 |
| 负载均衡 | 未配置 | 实现加权轮询 |

---

## 13. 神枢实现路线图

### 第一阶段: 基础架构 (2周)

```
神枢 App (Swift/Kotlin)
├── iSH-arm64 fork (Linux 运行时)
├── native_offload 桥接 (桩文件 + handler)
├── 会话文件系统 (/var/shuyu/ 布局)
└── ToolDispatch (JSONRPC dispatcher)
```

### 第二阶段: 模型系统 (2周)

```
ModelRouter
├── Provider 管理 (API Key + OAuth)
├── Agent Loop (故障转移 + 负载均衡)
├── 流式 SSE 输出
└── Thinking 模式渲染
```

### 第三阶段: 工具集成 (1周)

```
移植所有 apple-* 工具
├── HealthKit / HomeKit / Calendar
├── Vision (OCR/分类/人脸)
├── Location / Maps / Weather
└── Clipboard / Notification / Player
```

### 第四阶段: 生态系统 (1周)

```
集成外部组件
├── MinisSkills (MIT, 44技能直接导入)
├── MCP 子系统 (Python, 50KB源码)
├── 浏览器 (WKWebView)
└── 记忆系统 (GLOBAL.md + 每日日志)
```

### 第五阶段: 神枢特有 (持续)

```
神枢专属能力
├── 29.5亿语义空间集成
├── Black God 语言引擎 (shuyu_engine.py)
├── 枢语编译器集成
├── 自定义技能市场
└── 神枢 Agent 编排
```

---

## 附录 A: 文件索引

```
shuyu-reverse/
├── ARCHITECTURE.md                    本文档
├── SPEC.md                            接口规格 (本文件)
├── mcp-cli/                           MCP 子系统完整源码
├── shell/                             Shell 脚本 (shuyu-open, shuyu-mcp-cli)
├── skills/                            6 个已装技能 SKILL.md
├── configs/
│   ├── servers.json                   MCP 服务器配置
│   ├── GLOBAL.md                      全局凭证库
│   ├── env_vars.txt                   环境变量
│   ├── kernel_info.txt                内核信息
│   ├── os_release.txt                 OS 版本
│   ├── native_offload_patterns.txt   154条桥接日志
│   └── 2026-07-*.md                  每日记忆日志
└── tools.txt                         28个工具清单
```

---

> 神枢 = 枢语 Shuyu — Black God 定制语言 29.5亿语义空间
> 阿权/路飞 © 2026
