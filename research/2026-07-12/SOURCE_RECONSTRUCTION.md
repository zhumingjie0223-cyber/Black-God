# 神枢 (Shuyu) — 神枢 主应用源码重构

> 重构日期: 2026-07-12
> 数据源: APK 0.19-preview 反编译 (classes.dex 6.6MB) + GitHub Issues + Release Notes + 实时系统
> 状态: 主仓库未开源，以下为从 DEX/资源/日志 反推的完整架构和关键实现

---

## 一、包结构与类层级

```
com.openshuyu.app/
├── ShuyuApp.kt                          # Application 入口
├── MainActivity.kt                      # 主 Activity (聊天界面)
│
├── data/
│   ├── db/
│   │   ├── AppDatabase.kt               # Room 数据库 (主)
│   │   ├── ProviderDatabase.kt          # Provider 专用数据库
│   │   ├── MessageEntity.kt             # 消息实体
│   │   ├── ChatSessionEntity.kt         # 会话实体
│   │   ├── ProviderInstanceEntity.kt    # Provider 实例
│   │   ├── ProviderModelEntryEntity.kt  # 模型条目
│   │   ├── ProviderModelGroupEntity.kt  # 模型组
│   │   ├── ProviderAgentLoopIdEntity.kt # Agent Loop 模型池
│   │   ├── ProviderConfigMetaEntity.kt  # 配置元数据
│   │   ├── CompactMarkerEntity.kt       # 压缩标记
│   │   └── WebAppShortcutEntity.kt      # WebApp 快捷方式
│   │
│   └── model/
│       └── AgentContentPart.kt          # Agent 内容块 (含 ToolResult)
│
├── sandbox/
│   └── PtyBridge.kt                     # PTY 终端桥接 (JNI → libpty_bridge.so)
│
├── provider/
│   ├── ProviderModelsCache.kt           # 模型缓存
│   └── anthropic/
│       └── AnthropicModelsCache.kt      # Anthropic 专用缓存
│
├── service/
│   ├── AgentForegroundService.kt        # 前台服务 (悬浮窗 + 后台AI)
│   └── ToolOutcome.kt                   # 工具执行结果
│
├── offload/
│   ├── AlarmReceiver.kt                 # 闹钟接收器
│   ├── ScheduledNotificationReceiver.kt # 定时通知
│   └── MinisNotificationListenerService.kt  # 通知监听
│
├── scheduled/
│   └── ScheduledTaskAlarmReceiver.kt    # 定时任务触发器
│
├── accessibility/
│   └── MinisAccessibilityService.kt     # 无障碍服务 (UI自动化)
│
├── auth/
│   └── OAuthRedirectActivity.kt         # OAuth 回调处理
│
├── share/
│   └── ShareReceiverActivity.kt         # 系统分享接收
│
├── webapp/
│   └── WebAppActivity.kt               # WebApp 容器
│
├── crash/
│   ├── NativeCrashHandler.kt            # 原生崩溃处理 (JNI → libshuyu_crash_handler.so)
│   └── CrashFileSenderFactory.kt        # 崩溃日志发送
│
└── ui/
    └── chat/
        └── MemorySheetMode.kt           # 记忆面板 UI (Write 模式)
```

---

## 二、数据库 Schema

### 2.1 主数据库 (AppDatabase)

```kotlin
@Database(
    entities = [
        ChatSessionEntity::class,
        MessageEntity::class,
        CompactMarkerEntity::class,
        WebAppShortcutEntity::class,
    ],
    version = ?,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase()
```

#### ChatSessionEntity (sessions 表)

```kotlin
@Entity(tableName = "sessions")
data class ChatSessionEntity(
    @PrimaryKey val sessionId: String,        // UUID
    val title: String?,                        // 自动生成
    val startedAt: Long,                       // epoch millis
    val lastActive: Long,                      // epoch millis
    val messageCount: Int,
    val preview: String?,                      // 首条消息截断
    val source: String,                        // "chat" | "cli" | "scheduled"
    val modelEntryId: String?,                 // 使用的模型
    val providerInstanceId: String?            // 使用的 Provider
)
```

#### MessageEntity (messages 表)

```kotlin
@Entity(tableName = "messages")
data class MessageEntity(
    @PrimaryKey val messageId: String,         // UUID
    val sessionId: String,                      // FK → sessions
    val role: String,                           // "user" | "assistant" | "system" | "tool"
    val content: String,                        // 文本内容
    val thinking: String?,                      // 思考内容 (深度思考)
    val attachments: String?,                   // JSON 数组
    val toolCalls: String?,                     // JSON (工具调用)
    val timestamp: Long                         // epoch millis
)
```

### 2.2 Provider 数据库 (ProviderDatabase)

```kotlin
@Database(
    entities = [
        ProviderInstanceEntity::class,
        ProviderModelEntryEntity::class,
        ProviderModelGroupEntity::class,
        ProviderAgentLoopIdEntity::class,
        ProviderConfigMetaEntity::class,
    ],
    version = ?,
    exportSchema = false
)
abstract class ProviderDatabase : RoomDatabase()
```

#### ProviderInstanceEntity (provider_instances 表)

```kotlin
@Entity(tableName = "provider_instances")
data class ProviderInstanceEntity(
    @PrimaryKey val id: String,               // UUID
    val label: String,                          // 显示名称 (如 "Anthropic 3")
    val providerType: String,                   // "openAI"|"anthropic"|"gemini"|"openRouter"
    val credentialType: String,                 // "apiKey" | "oauth"
    val isEnabled: Boolean,
    val customBaseURL: String?,                 // 自定义端点
    val appendV1Suffix: Boolean,                // 是否追加 /v1
    val imageEndpointMode: String               // "auto"|"separate"|"disabled"
)
```

#### ProviderModelEntryEntity (provider_model_entries 表)

```kotlin
@Entity(tableName = "provider_model_entries")
data class ProviderModelEntryEntity(
    @PrimaryKey val entryId: String,           // "providerUUID/model_id"
    val providerInstanceId: String,             // FK
    val modelId: String,                        // API model ID
    val displayName: String,                    // 显示名称
    val isCustom: Boolean,                      // 手动添加 vs API发现
    val isHidden: Boolean,                      // 隐藏
    val contextWindow: Int,                     // 上下文窗口 (tokens)
    val contextWindowOverride: Int?,            // 用户覆盖
    val maxOutputTokens: Int?,                  // 最大输出覆盖
    val modalities: String,                     // JSON 数组
    val modalitiesOverride: String?,            // JSON (用户覆盖)
    val supportsTools: Boolean,
    val supportsVision: Boolean
)
```

#### ProviderAgentLoopIdEntity (provider_agent_loop_ids 表)

```kotlin
@Entity(tableName = "provider_agent_loop_ids")
data class ProviderAgentLoopIdEntity(
    @PrimaryKey val entryId: String,           // 模型条目 ID
    val priority: Int,                          // 顺序 (FAILOVER 用)
    val weight: Int?                            // 权重 (LOAD_BALANCE 用)
)
```

---

## 三、SharedPreferences 键值表

| Key | 类型 | 用途 |
|-----|------|------|
| `shuyu_config_enabled` | Boolean | shuyu-config 开关 |
| `shuyu_config_permission` | Boolean | 权限状态 |
| `shuyu_memory_prefs` | String (JSON) | 记忆系统设置 |
| `shuyu_enhanced_cache_prefs` | String (JSON) | 增强缓存设置 |
| `shuyu_scheduled_tasks_prefs` | String (JSON) | 定时任务列表 |
| `shuyu_alarms_prefs` | String (JSON) | 闹钟配置 |
| `shuyu_settings` | String (JSON) | 通用设置 |
| `shuyu_skills_browser` | Boolean | 技能浏览器状态 |
| `shuyu.current_chat_session_id` | String | 当前会话 ID |

---

## 四、原生库 (JNI)

| .so 文件 | 功能 |
|----------|------|
| `libproot.so` | PRoot Linux 容器引擎 |
| `libproot-loader.so` | PRoot 64位加载器 |
| `libproot-loader32.so` | PRoot 32位加载器 |
| `libpty_bridge.so` | PTY 终端桥 (stdin/stdout 管道 → App) |
| `libshuyu_crash_handler.so` | 原生崩溃捕获 (Breakpad/Sentry) |
| `libtalloc.so` | 内存池 (PRoot 依赖) |
| `libc++_shared.so` | LLVM C++ STL |
| `libandroidx.graphics.path.so` | AndroidX 图形路径 |
| `libdatastore_shared_counter.so` | DataStore 共享计数器 |

---

## 五、Android Assets 结构

```
assets/
├── alpine-minirootfs.tar          # Alpine Linux 根文件系统
├── proot-aarch64                  # PRoot 可执行文件 (备用)
├── models-dev-api.json            # 模型 API 元数据目录
├── dexopt/
│   ├── baseline.prof              # ART 性能配置
│   └── baseline.profm             # 同上 (metadata)
├── katex/                         # KaTeX 数学渲染引擎
│   ├── katex.min.css
│   ├── katex.min.js
│   ├── katex-render.html
│   ├── mhchem.min.js
│   └── fonts/                     # 20 个字体文件
└── default_mount/                 # 初始 Linux 文件系统
    ├── etc/
    │   ├── hostname
    │   ├── pip/pip.conf
    │   └── profile.d/shuyu.sh
    └── usr/local/
        ├── bin/
        │   ├── shuyu-open          # OSC 1337 发射器
        │   ├── shuyu-mcp-cli       # MCP CLI shim
        │   ├── xdg-open            # → shuyu-open 软链
        │   ├── www-browser         # → shuyu-open 软链
        │   └── sensible-browser    # → shuyu-open 软链
        └── lib/shuyu-mcp-cli/      # MCP Python 实现 (完整源码)
            ├── main.py
            ├── daemon.py
            ├── transport/
            │   ├── __init__.py
            │   ├── http.py
            │   └── stdio.py
            └── utils/
                ├── __init__.py
                ├── config.py
                └── deps.py
```

---

## 六、关键系统流程

### 6.1 冷启动流程

```
Application.onCreate()
  → 初始化 CrashHandler (libshuyu_crash_handler.so)
  → 初始化 Room 数据库
  → 加载 Provider 配置 (后台线程)
  → 加载 Agent Loop 模型池
  → 启动 PTY Bridge (libpty_bridge.so)
  → 解压 alpine-minirootfs.tar (首次)
  → 挂载 /var/shuyu/ 文件系统
  → 启动 PRoot (libproot.so)
  → 注入 default_mount 文件
  → 启动 AgentForegroundService (如需要后台)
```

### 6.2 对话流程

```
用户输入
  → MainActivity.onSend(message)
  → 创建 MessageEntity (role="user")
  → 插入 Room DB
  → 构建 System Prompt:
      - SOUL.md 人设
      - GLOBAL.md 全局记忆
      - 每日日志 (YYYY-MM-DD.md)
      - 已启用技能 SKILL.md
      - 工具列表 (从 native_offload 桩枚举)
  → Agent Loop 选模型
  → 调用 shuyu-model-use run
  → 流式 SSE 输出
  → UI 逐词渲染 (时间/换行双策略)
  → 检测工具调用 → 拦截 → shell_execute → 结果回传
  → 循环直到 AI 输出完成
  → 保存 MessageEntity (role="assistant")
  → 生成会话标题 (子模型 + 首尾消息对)
```

### 6.3 native_offload 调用链

```
AI: 调用 shell_execute("shuyu-model-use run --model xxx")
  → PRoot/PTY 执行 shell 命令
  → exec("/usr/local/bin/shuyu-model-use")
  → iSH/PRoot 内核: 检测 0 字节文件
  → native_offload 钩子触发
  → 参数通过 Parcel/JSON 传到宿主 App
  → Kotlin ModelRouter 处理
  → HTTP API 调用 (OkHttp)
  → JSON 结果写回 stdout
  → PTY 回传 shell_execute
```

---

## 七、神枢重建对应关系

| 神枢 组件 | 神枢对应 | 来源 |
|-----------|---------|------|
| `com.openshuyu.app.ShuyuApp` | `com.shuyu.app.ShuyuApp` | 重新实现 |
| `MainActivity.kt` | `ShuyuMainActivity.kt` | 重新实现 |
| `AppDatabase` (Room) | `ShuyuDatabase` (Room/SQLDelight) | Schema 已知, 重实现 |
| `ProviderDatabase` (Room) | `ShuyuProviderDatabase` | Schema 已知, 重实现 |
| `PtyBridge.kt` | `ShuyuPtyBridge.kt` | JNI 接口已知, 复用 .so |
| `ProviderModelsCache.kt` | `ShuyuModelsCache.kt` | 接口已知 |
| `AgentForegroundService.kt` | `ShuyuForegroundService.kt` | 重新实现 |
| MCP Python | MCP Python | **源码完整, 直接复用** |
| shuyu-open | shuyu-open | **源码完整, 改名复用** |
| ish-arm64 (C) | ish-arm64 fork | GitHub 完整源码 |
| proot (C) | proot fork | GitHub 完整源码 |

---

## 八、关键文件一览

| 文件 | 大小 | 来源 | 神枢可用性 |
|------|------|------|-----------|
| APK classes.dex | 6.6MB | APK 解压 | 反编译为架构参考 |
| MCP Python (8文件) | 50KB | APK assets + 实时系统 | ✅ 直接复用 |
| shuyu-open / shuyu-mcp-cli | 4.5KB | APK assets | ✅ 改名复用 |
| models-dev-api.json | ? | APK assets | ✅ 模型目录复用 |
| alpine-minirootfs.tar | ? | APK assets | ✅ Linux rootfs 复用 |
| ish-arm64 (516文件) | 9.1MB | GitHub | ✅ GPLv3 fork |
| proot (330文件) | 3.3MB | GitHub | ✅ GPLv2 fork |
| MinisSkills (44技能) | ~200KB | GitHub | ✅ MIT 直接导入 |
| 28个工具接口规格 | - | 实时逆向 | ✅ 全接口已知 |

---

> 神枢 = 枢语 Shuyu — Black God 定制语言 29.5亿语义空间
> 阿权/路飞 © 2026
