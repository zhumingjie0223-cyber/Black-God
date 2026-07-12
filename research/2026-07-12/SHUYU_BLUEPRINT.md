# 神枢(Shuyu) — 全平台整合蓝图 v4.0

> 日期: 2026-07-12
> 整合: bolt.new (MIT) + Minis逆向 + Manus架构 + Hercules参考
> 目标: 无遗漏、可直接fork开干的完整方案

---

## 零、四个平台一句话总结

| 平台 | 一句话 | 拿到什么 |
|------|--------|---------|
| **bolt.new** | AI聊天造应用 | ✅ 完整源码(MIT), 172文件 TypeScript |
| **Minis** | AI Agent运行环境 | ✅ 接口100% + MCP源码 + Shell脚本 |
| **Manus** | 通用任务Agent | 🟡 架构可抄(todo.md+沙箱+流式) |
| **Hercules** | AI造应用(SaaS) | 🔴 闭源, 仅功能参考 |

---

## 一、bolt.new 源码架构 (完全解析)

### 1.1 技术栈

```
前端: Remix (React SSR) + Cloudflare Pages
AI:    Vercel AI SDK (ai@3.3.4) + @ai-sdk/anthropic
模型:   Claude 3.5 Sonnet (anthropic.claude-3-5-sonnet-20240620)
执行:   StackBlitz WebContainer (浏览器内Node.js)
状态:   @nanostores (轻量状态管理)
编辑器: CodeMirror 6 + xterm.js
样式:   UnoCSS + Radix UI + Framer Motion
```

### 1.2 核心文件拓扑

```
bolt.new/
├── app/
│   ├── entry.client.tsx          # 客户端入口
│   ├── entry.server.tsx           # 服务端入口(SSR)
│   ├── root.tsx                   # 根布局
│   ├── lib/
│   │   ├── .server/
│   │   │   └── llm/
│   │   │       ├── api-key.ts     # API Key管理
│   │   │       ├── constants.ts   # MAX_TOKENS=8192, MAX_RESPONSE_SEGMENTS=2
│   │   │       ├── model.ts       # 模型工厂: createAnthropic(apiKey)('claude-3-5-sonnet')
│   │   │       ├── prompts.ts     # 🔥核心: 14KB系统提示词
│   │   │       ├── stream-text.ts # 流式文本: streamText() 包装
│   │   │       └── switchable-stream.ts # 可切换流: token超限自动续传
│   │   ├── stores/               # 状态管理(nanostores)
│   │   ├── runtime/              # WebContainer运行时
│   │   ├── hooks/                # React hooks
│   │   └── webcontainer/         # WebContainer API封装
│   ├── components/
│   │   ├── chat/                  # 聊天界面
│   │   ├── editor/                # CodeMirror编辑器
│   │   ├── workbench/             # 工作台(预览+终端+文件树)
│   │   └── ui/                    # UI组件库
│   └── routes/
│       ├── _index.tsx             # 首页
│       ├── api.chat.ts            # 🔥核心: /api/chat 路由(流式AI)
│       ├── api.enhancer.ts        # 提示词增强
│       └── chat.$id.tsx           # 会话页面
├── package.json                   # 52依赖
├── wrangler.toml                  # CF Workers配置
└── vite.config.ts                 # Vite构建配置
```

### 1.3 AI对话流程 (从源码逆推)

```
POST /api/chat { messages: [...] }
    │
    ▼
api.chat.ts: chatAction()
    │
    ├── 1. 创建 SwitchableStream (可切换流)
    │
    ├── 2. streamText(messages, env, options)
    │       │
    │       ├── getSystemPrompt()     ← 14KB提示词注入
    │       ├── getAnthropicModel()   ← Claude 3.5 Sonnet
    │       ├── getAPIKey(env)        ← CF环境变量
    │       └── convertToCoreMessages ← Vercel AI SDK格式转换
    │
    ├── 3. 流式返回 → onFinish回调
    │       │
    │       ├── finishReason='length' → 超token限制
    │       │   ├── 检查switch次数 < MAX_RESPONSE_SEGMENTS(2)
    │       │   ├── 追加 CONTINUE_PROMPT 到消息列表
    │       │   └── stream.switchSource(新流) ← 自动续传
    │       │
    │       └── finishReason≠'length' → stream.close()
    │
    └── 4. Response(text/plain; charset=utf-8) → 前端SSE解析
```

### 1.4 System Prompt 核心机制

bolt.new 的 14KB 系统提示词包含:

```
<system_constraints>
  WebContainer: 浏览器内Node.js, 无pip/无C++/无原生二进制
  可用命令: cat, chmod, curl, node, python3, wasm, jq...
</system_constraints>

<artifact_info>
  boltArtifact: 单次完整产物
    └── boltAction type="shell|file"
          ├── shell: npm install && npm run dev
          └── file: 完整文件内容(路径+代码)
</artifact_info>

<diff_spec>
  用户修改以 <diff> 或 <file> 格式传入
</diff_spec>
```

**关键设计**:
- AI输出用 `<boltArtifact>` + `<boltAction>` XML标签结构化
- 不是自由对话, 而是**结构化代码生成**
- 每次输出必须是完整的、可执行的产物
- 禁止使用占位符("// rest of code...")

### 1.5 WebContainer 运行时

```
浏览器进程
  ├── WebContainer API (Chrome)
  │   ├── 虚拟文件系统
  │   ├── Node.js 运行时 (无原生二进制)
  │   ├── npm/yarn 包管理
  │   ├── 虚拟终端 (xterm.js)
  │   └── HTTP服务器 (localhost)
  └── iframe 预览
```

---

## 二、神枢合成方案

### 2.1 整体架构

```
┌──────────────────────────────────────────────────┐
│                 神枢 (Shuyu)                       │
│                                                   │
│  ┌─────────────────┐  ┌───────────────────────┐   │
│  │  神枢 Chat       │  │  神枢 Builder          │   │
│  │  ← Minis Agent   │  │  ← bolt.new 引擎       │   │
│  │  对话+工具+系统   │  │  聊天→代码→部署         │   │
│  └────────┬────────┘  └───────────┬───────────┘   │
│           │                       │               │
│  ┌────────▼───────────────────────▼───────────┐   │
│  │            神枢 Core                        │   │
│  │  ┌─────────────────────────────────────┐   │   │
│  │  │ AI Gateway (模型分档路由)             │   │   │
│  │  │ Claude三档+Gemini+DeepSeek+小模型    │   │   │
│  │  │ ← Minis Provider系统 + Manus分档思想 │   │   │
│  │  ├─────────────────────────────────────┤   │   │
│  │  │ Runtime (执行层)                     │   │   │
│  │  │ ← Minis MCP + ish-arm64 + WebContainer│   │   │
│  │  ├─────────────────────────────────────┤   │   │
│  │  │ Skills (技能库)                      │   │   │
│  │  │ ← MinisSkills 44个 + bolt.new提示词 │   │   │
│  │  ├─────────────────────────────────────┤   │   │
│  │  │ Memory (记忆系统)                    │   │   │
│  │  │ ← GLOBAL.md + 每日日志 + todo.md    │   │   │
│  │  └─────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────┘   │
│                                                   │
│  ┌─────────────────────────────────────────┐     │
│  │         部署层                            │     │
│  │  CF Workers/Pages + GCP (SG/HK/US)       │     │
│  │  + 神枢域名                                │     │
│  └─────────────────────────────────────────┘     │
└──────────────────────────────────────────────────┘
```

### 2.2 bolt.new → 神枢 直接迁移清单

| bolt.new 组件 | 神枢对应 | 迁移方式 |
|--------------|---------|---------|
| `app/lib/.server/llm/prompts.ts` | 神枢 Builder Prompt | 直接复用, 改品牌名 |
| `app/lib/.server/llm/stream-text.ts` | 神枢 AI Stream | 改模型→神枢网关 |
| `app/lib/.server/llm/switchable-stream.ts` | 神枢续传流 | 直接复用 |
| `app/routes/api.chat.ts` | `/api/shuyu/build` | 改路由名 |
| `app/components/chat/` | 神枢聊天界面 | 改UI风格 |
| `app/components/workbench/` | 神枢工作台 | 复用预览+终端 |
| `app/components/editor/` | 神枢编辑器 | 复用CodeMirror |
| `package.json` | 神枢依赖 | 精简+加神枢特有 |

### 2.3 模型从 bolt.new 的 Claude 3.5 → 神枢分档路由

bolt.new 目前只用一个模型(`claude-3-5-sonnet-20240620`)。

神枢改造后:

```typescript
// bolt.new 原版
return anthropic('claude-3-5-sonnet-20240620');

// 神枢改造: 分档路由
function getShuyuModel(task: string, complexity: 'low'|'medium'|'high'|'max') {
  switch(complexity) {
    case 'low':    return anthropic('claude-haiku-4-5');        // 小改动
    case 'medium': return anthropic('claude-sonnet-4-6');      // 常规代码
    case 'high':   return anthropic('claude-sonnet-5-xhigh');  // 复杂重构
    case 'max':    return anthropic('claude-opus-4-8-high');   // 架构设计
  }
}
```

### 2.4 Minis 28个工具 → 神枢系统集成

| Minis工具 | 神枢用途 |
|-----------|---------|
| `apple-healthkit` | 健康数据Agent |
| `apple-homekit` | 智能家居Agent |
| `apple-calendar/reminders` | 日程Agent |
| `apple-vision` | 图片分析(OCR/分类/人脸) |
| `apple-maps/location` | 位置服务 |
| `apple-clipboard` | 剪贴板操作 |
| `shuyu-browser-use` | 浏览器自动化 |
| `shuyu-model-use` | AI模型调用 |
| `shuyu-sessions-cli` | 会话管理 |
| `shuyu-config` | 系统配置 |
| `shuyu-mcp-cli` | MCP集成 |

### 2.5 Manus todo.md 驱动 → 神枢长任务机制

```
用户: "帮我做一个电商网站"
    │
    ▼
神枢 Planner: 生成 todo.md
    ├── [ ] 1. 创建项目结构 (package.json + vite配置)
    ├── [ ] 2. 搭建首页布局 (Header + Hero + Footer)  
    ├── [ ] 3. 实现商品列表页 (API + 卡片组件)
    ├── [ ] 4. 添加购物车功能 (状态管理 + 结算)
    ├── [ ] 5. 集成支付 (Stripe Checkout)
    └── [ ] 6. 部署到 Cloudflare
    │
    ▼
神枢 Executor: 逐步执行
    每完成一步 → todo.md 标记 [x]
    上下文过长 → 重读 todo.md 找回目标
    │
    ▼
神枢 Stream: events.shuyu.app 实时推送进度
```

---

## 三、实施路线图 (分阶段)

### Phase 1: Fork & Rebrand (2天)

```
- Fork stackblitz/bolt.new → shuyu-org/shuyu-builder
- 全局替换: bolt → shuyu, Bolt → 神枢
- 改 wrangler.toml → shuyu-builder.workers.dev
- 改系统提示词品牌名
```

### Phase 2: 模型升级 (3天)

```
- 替换单模型为分档路由
- 接入神枢 AI 网关
- 添加 Gemini/DeepSeek 备份
- 实现 SwitchableStream 多模型切换
```

### Phase 3: 神枢 Agent 融合 (5天)

```
- 集成 Minis 28个工具到 Builder 侧边栏
- 添加 MCP 子系统
- 实现 todo.md 长任务规划
- 接入 GLOBAL.md 记忆系统
- 添加 TG 推送集成
```

### Phase 4: 部署与发布 (3天)

```
- CF Workers 部署
- 神枢域名绑定
- 技能市场(MinisSkills集成)
- App Store/Google Play打包
```

---

## 四、bolt.new 依赖精简方案

当前52个依赖 → 神枢精简到约25个:

**保留 (核心)**:
- `@ai-sdk/anthropic`, `ai` (AI SDK)
- `@webcontainer/api` (浏览器运行时)
- `@remix-run/cloudflare*` (SSR框架)
- `@nanostores/react`, `nanostores` (状态)
- `react`, `react-dom`
- `@codemirror/*` (编辑器)
- `@xterm/*` (终端)
- `framer-motion` (动画)

**替换**:
- UnoCSS → Tailwind CSS (神枢现有)
- Radix UI → shadcn/ui (神枢现有)
- `shiki` → 保留 (语法高亮)

**删除** (神枢不需要):
- isbot, date-fns(可用dayjs替), jose(内部用)

---

## 五、关键代码片段

### 5.1 神枢 Builder API 路由

```typescript
// app/routes/api.shuyu.build.ts
import { streamText } from '~/lib/.server/llm/stream-text';
import SwitchableStream from '~/lib/.server/llm/switchable-stream';
import { getShuyuModel } from '~/lib/.server/llm/shuyu-model';
import { getShuyuPrompt } from '~/lib/.server/llm/shuyu-prompt';

export async function action({ request, context }: ActionFunctionArgs) {
  const { messages, complexity = 'medium' } = await request.json();
  const stream = new SwitchableStream();
  
  const result = await streamText({
    model: getShuyuModel(complexity),
    system: getShuyuPrompt(),
    messages,
    env: context.cloudflare.env,
    onFinish: async ({ finishReason }) => {
      if (finishReason === 'length' && stream.switches < 3) {
        // 神枢自动续传(最多3段)
        const continued = await streamText({...});
        stream.switchSource(continued.toAIStream());
      }
    }
  });
  
  return new Response(result.toAIStream());
}
```

### 5.2 神枢模型分档工厂

```typescript
// app/lib/.server/llm/shuyu-model.ts
export function getShuyuModel(complexity: string) {
  switch(complexity) {
    case 'low':    return anthropic('claude-haiku-4-5');
    case 'medium': return anthropic('claude-sonnet-4-6');
    case 'high':   return anthropic('claude-sonnet-5');
    case 'max':    return anthropic('claude-opus-4-8');
    default:       return anthropic('claude-sonnet-4-6');
  }
}

// 后备模型 (Anthropic挂了用Gemini)
export function getFallbackModel() {
  return google('gemini-2.5-pro');
}
```

---

## 六、完整文件索引

```
shuyu-reverse/
├── ARCHITECTURE.md              # Minis架构
├── SPEC.md                      # Minis接口规格(13章)
├── SOURCE_RECONSTRUCTION.md     # Minis源码重构
├── bolt-new-source/             # 🔥 bolt.new源码
│   ├── app/lib/.server/llm/
│   │   ├── prompts.ts           # 14KB系统提示词
│   │   ├── stream-text.ts       # 流式文本
│   │   ├── switchable-stream.ts # 可切换流
│   │   ├── model.ts             # 模型工厂
│   │   └── constants.ts         # 常量
│   ├── app/routes/api.chat.ts   # 聊天API
│   ├── package.json             # 52依赖清单
│   └── wrangler.toml            # CF配置
├── manus-analysis/              # Manus架构分析
├── hercules/                    # Hercules分析
├── mcp-cli/                     # MCP Python源码
├── shell/                       # Shell脚本(shuyu-open等)
├── skills/                      # 6个技能SKILL.md
└── configs/                     # 配置+环境变量
```

---

> 神枢 = bolt.new引擎 + Minis工具系统 + Manus规划机制 + 神枢AI网关
> 阿权/路飞 © 2026
