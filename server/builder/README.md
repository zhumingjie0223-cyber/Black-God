# 神枢 Builder — bolt.new 源码集成说明

## 来源
stackblitz/bolt.new — MIT License
GitHub: https://github.com/stackblitz/bolt.new
16,456 stars / 14,700 forks

## 已集成的核心文件

| 文件 | 用途 | 来源 |
|------|------|------|
| system-prompt.ts | 14KB AI系统提示词,boltArtifact/boltAction协议 | prompts.ts |
| stream-text.ts | 流式AI调用封装(Vercel AI SDK) | stream-text.ts |
| switchable-stream.ts | 可切换流(token超限自动续传) | switchable-stream.ts |
| model-factory.ts | 模型工厂(createAnthropic) | model.ts |
| chat-route.ts | /api/chat 路由 | api.chat.ts |
| constants.ts | MAX_TOKENS=8192 | constants.ts |

## 神枢改造计划

目前bolt.new只用单个模型(claude-3-5-sonnet)，神枢改造后接入分档路由:

```
model-factory.ts 改造方向:
  complexity=trivial → haiku
  complexity=low     → sonnet-low
  complexity=medium  → sonnet-medium
  complexity=high    → sonnet-xhigh
  complexity=max     → opus-high
```

## 依赖
- @ai-sdk/anthropic
- ai (Vercel AI SDK v3)
- @webcontainer/api (浏览器内Node.js运行时)
