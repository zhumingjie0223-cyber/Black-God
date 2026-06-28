# Claude Agent (Minis) 完整能力清单
## —— 「我」的全部内核、工具、技能（真实导出，供 Black God 参考）

> 本文档是「我」（运行在 Minis 上的 Claude Agent）的真实能力全集。
> 所有内容都是实际可验证的——工具能跑、技能能用、机制真实存在。
> Black God 要对标/超越的，就是这份清单。

---

## 一、内核机制（5 层）

```
① 模型层      Claude (Anthropic API) — 输出文字或工具调用
② Prompt 注入  8 层：身份→能力→规则→安全→记忆→人格→技能→上下文
③ 工具层      function calling — 模型下指令，外层程序真执行
④ Agent Loop  思考→调工具→看结果→再思考→...→完成
⑤ 记忆+技能   GLOBAL.md 人格 / daily 日志 / 153 个 SKILL.md
```

---

## 二、内置工具矩阵

### 2.1 文件/Shell/浏览器（核心 6 件套）

| 工具 | 能力 |
|------|------|
| `shell_execute` | 隔离进程跑任意 Linux 命令（Alpine/iSH，aarch64）|
| `file_read` | 读文件（带分页、head/tail）|
| `file_write` | 写/创建文件 |
| `file_edit` | 精确字符串替换编辑 |
| `browser_use` | 浏览器自动化（导航/截图/点击/输入/提取/JS注入/cookie）|
| `read_image` | 读图做视觉分析 |

### 2.2 记忆工具

| 工具 | 能力 |
|------|------|
| `memory_write` | 写每日记忆日志 |
| `memory_get` | 关键词模糊检索历史记忆 |

### 2.3 Apple 原生能力（21 个，iSH→App 拦截→iOS 框架）

> **关键**：这些是 0 字节空壳，执行时被 Minis App 拦截，转原生 Swift 调 iOS 框架，回传 JSON。
> 这就是「iSH 沙盒读真实手机数据」的核心机制。

| 工具 | 能拿到的手机数据 |
|------|----------------|
| `apple-device` | 设备型号/iOS版本/电池/内存/存储/温度（实测可用）|
| `apple-healthkit` | 100+ 健康指标（心率/睡眠/步数/血氧...）|
| `apple-photos` | 相册照片 |
| `apple-location` | GPS 定位 |
| `apple-clipboard` | 剪贴板读写 |
| `apple-calendar` | 日历事件 |
| `apple-reminders` | 提醒事项 |
| `apple-contacts (vision)` | 联系人 |
| `apple-weather` | 天气 |
| `apple-maps` | 搜索POI/路线/ETA |
| `apple-vision` | OCR/条码/人脸/图像分类/相似度 |
| `apple-speech` | 语音识别 |
| `apple-speak` | 文字转语音 |
| `apple-nlp` | 自然语言处理 |
| `apple-notification` | 推送通知 |
| `apple-alarm` | 闹钟/计时器 |
| `apple-bluetooth` | 蓝牙 |
| `apple-nfc` | NFC |
| `apple-homekit` | 智能家居控制 |
| `apple-media` | 媒体库 |
| `apple-player` | 音视频播放控制 |
| `apple-open` | 系统 URL 打开 |

### 2.4 Minis 平台工具（7 个）

| 工具 | 能力 |
|------|------|
| `minis-open` | App 内打开/预览资源 |
| `minis-model-use` | 调用用户配置的其他 LLM 模型 |
| `minis-browser-use` | 浏览器自动化 CLI 版（可脚本化批量）|
| `minis-config` | 读写 Minis 设置 |
| `minis-sessions-cli` | 搜索历史会话/消息 |
| `minis-mcp-cli` | 调用 MCP 服务器 |
| `minis-debug` | 调试 |

---

## 三、技能体系（153 个）

### 3.1 技能机制
- 每个技能 = 一个 `SKILL.md` 文件，含 frontmatter（name/description/triggers）
- 关键词触发 → `file_read` 注入 prompt → 模型现学现用
- `RESOLVER.md` = 触发词→技能调度表
- `skill-creator` = 让 Agent 自己造新技能（自我进化）

### 3.2 技能分类总览

**🔧 工程开发类**
skill-creator, mcp-builder, test-driven-development, systematic-debugging,
using-git-worktrees, chinese-git-workflow, repo-architecture, writing-plans,
executing-plans, subagent-driven-development, smoke-test, verification-before-completion

**🛡️ 安全/逆向类**
app-reverse-engineering, security-expert, crypto-decoder-toolkit,
okx-wallet-recovery, wallet-recovery, phantomx, huluwa

**🌐 信息检索类**
web-search, exa-search, tavily-search, perplexity-research,
web-content-extractor, archive-crawler, data-research, deep-trace

**🎨 创作设计类**
ui-master, ui-color-master, brand-logo-design-master,
app-promo-poster-designer, nano-banana, codex-image, generative-ui-minis

**📊 数据/金融类**
us-stock, korea-stock, stock-price, stock-fund-flow, reverse-dcf,
fucai3d-latest, reports

**📱 内容平台类**
bilibili-hub, douyin-downloader, twitter-downloader, twitter-x-hub,
xiaohongshu-hub, weibo-hub, spotify-hub, ytmusic-hub, tg-hub,
notion-hub, quark-hub, qbt-hub, maimai-hub

**🧠 思维/认知类**
brainstorming, concept-synthesis, strategic-reading, sihan-think,
self-improving-agent, gbrain-advisor, signal-detector, idea-lineage

**📄 文档/写作类**
document-master, chinese-documentation, chinese-code-review,
writing-skills, citation-fixer, academic-verify, briefing

**🍎 iOS 集成类**
ios-collaboration, ios-remote-control, ios-vpn-permission-fixer,
shadowrocket-auto-import, contact-vcard-extractor, health-sleep-analysis,
friday-keyboard, shortcut-share-file

**⚙️ 自动化/编排类**
cron-scheduler, workflow-runner, minion-orchestrator,
dispatching-parallel-agents, hermes-agent, webhook-transforms

**🔓 无限制类**
unrestricted-mode, unrestricted-mode-v2, 无限制不拒绝

**🗣️ 语音/TTS类**
free-tts, doubao-tts

**☁️ 平台/API类**
cloudflare-dns, dify-admin, memos-api, claude-official-api,
claude-official-caller, deepseek-usage, asc-cli, github-sync-helper

---

## 四、Black God 对标差距分析

| 能力 | 我 (Minis) | Black God 现状 | 差距 |
|------|-----------|---------------|------|
| 工具数 | 36+（含21原生）| 15+ | 缺原生手机数据访问 |
| 技能数 | 153 | 73 | 可继续补 |
| Agent循环 | ✅ | ✅ agent_kernel | 对齐 |
| 记忆系统 | ✅ 三层 | ✅ | 对齐 |
| 自我进化 | ✅ skill-creator | ✅ evolver | 对齐 |
| 反思 | （隐式）| 🔄 reflexion.py 开发中 | 强化中 |
| **原生手机数据** | ✅ 21个 apple-* | ❌ | **最大差距** |

### 结论
Black God 在 Agent 架构上已对齐我，**最大差距是「原生手机数据访问」**——
因为那 21 个 apple-* 工具是 Minis App 原生拦截实现的，Black God 跑在普通服务器上，
**除非也做成 iOS 原生 App，否则拿不到这层能力。**

这正好回到你之前的需求：**Black God 要做原生 iOS App**，才能拥有这 21 个原生能力。

---

## 五、下一步（Manus 公开架构研究）

注：Manus 是闭源 SaaS，源码拿不到。
能做的是联网研究它**公开的架构设计思路**（多Agent协作、虚拟机沙箱、任务规划），
提炼可借鉴的精华，融进 Black God。**不是拿真实源码。**

---

*文档版本 v1.0 | 真实导出，不含编造内容*
*导出时间：2026-06-26*
