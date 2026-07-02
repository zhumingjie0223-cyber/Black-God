# Using the Messages API

**来源**: https://platform.claude.com/docs/en/build-with-claude/working-with-messages

Practical patterns and examples for using the Messages API effectively.

---

## API 对比

Anthropic 提供两种构建方式：

| 特性 | Messages API | Claude Managed Agents |
|------|--------------|----------------------|
| **定义** | 直接模型提示访问 | 预构建、可配置的 Agent 框架，运行在托管基础设施 |
| **适用场景** | 自定义 Agent 循环和细粒度控制 | 长时间运行任务和异步工作 |

> **Zero Data Retention (ZDR)**: 当组织有 ZDR 协议时，通过此功能发送的数据在 API 响应返回后不会存储。

---

## 基本请求与响应

### 重要更新
**Claude Opus 4.7 及更高版本**（包括 Claude Opus 4.8）**不支持** `temperature`、`top_p`、`top_k` 采样参数。设置非默认值会返回 400 错误。请省略这些参数，使用提示词引导模型行为。

### Python 示例

```python
message = anthropic.Anthropic().messages.create(
    model="claude-opus-4-8",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello, Claude"}],
)
print(message)
```

### 响应输出

```json
{
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "Hello!"
    }
  ],
  "model": "claude-opus-4-8",
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 12,
    "output_tokens": 6
  }
}
```

**拒绝响应**: Claude Opus 4.7+ 的拒绝响应（`stop_reason: "refusal"`）包含 `stop_details` 对象，标识触发拒绝的策略类别。

---

## 多轮对话

Messages API 是**无状态**的，需要始终发送完整的对话历史。可以使用合成的 assistant 消息构建对话。

### Python 示例

```python
message = anthropic.Anthropic().messages.create(
    model="claude-opus-4-8",
    max_tokens=1024,
    messages=[
        {"role": "user", "content": "Hello, Claude"},
        {"role": "assistant", "content": "Hello!"},
        {"role": "user", "content": "Can you describe LLMs to me?"},
    ],
)
print(message)
```

### 响应输出

```json
{
  "id": "msg_018gCsTGsXkYJVqYPxTgDHBU",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "Sure, I'd be happy to provide..."
    }
  ],
  "model": "claude-opus-4-8",
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 30,
    "output_tokens": 309
  }
}
```

---

## 中途系统消息（System Role in Messages）

**Claude Opus 4.8** 支持在用户轮次后插入 `"role": "system"` 消息，在对话中途添加新的系统指令。

### 规则
- 系统消息**不能**作为 `messages` 的第一条（首条指令使用顶级 `system` 字段）
- 中途系统消息与顶级 `system` 字段具有相同权限
- 因追加到历史末尾，不会使之前的缓存前缀失效

### 使用场景
- **顶级 `system` 字段**: 从第一轮开始适用的指令
- **中途系统消息**: 仅在后续才相关的指令

可与 **Prompt Caching** 结合使用。

---

## Prefill（预填充 Claude 的回复）

在 `messages` 列表的最后位置预填充 Claude 回复的部分内容，用于引导响应。

### ⚠️ 限制
**不支持 Prefill 的模型**:
- Claude Fable 5
- Claude Mythos 5 / Mythos Preview
- Claude Opus 4.8 / 4.7 / 4.6
- Claude Sonnet 4.6

使用这些模型会返回 400 错误。替代方案：使用 **Structured Outputs** 或系统提示指令。

### Python 示例（支持的模型）

```python
message = anthropic.Anthropic().messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1,
    messages=[
        {
            "role": "user",
            "content": "What is latin for Ant? (A) Apoidea, (B) Rhopalocera, (C) Formicidae",
        },
        {"role": "assistant", "content": "The answer is ("},
    ],
)
print(message)
```

### 响应输出

```json
{
  "id": "msg_01Q8Faay6S7QPTvEUUQARt7h",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "C"
    }
  ],
  "model": "claude-sonnet-4-5",
  "stop_reason": "max_tokens",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 42,
    "output_tokens": 1
  }
}
```

---

## Vision（视觉能力）

Claude 可以读取文本和图像。图像支持 `base64`、`url`、`file` 三种来源类型。

### 支持的媒体类型
- `image/jpeg`
- `image/png`
- `image/gif`
- `image/webp`

### Python 示例

```python
import base64
import httpx

# 选项 1: Base64 编码图像
image_url = "https://upload.wikimedia.org/wikipedia/commons/a/a7/Camponotus_flavomarginatus_ant.jpg"
image_media_type = "image/jpeg"
image_data = base64.standard_b64encode(httpx.get(image_url).content).decode("utf-8")

message = anthropic.Anthropic().messages.create(
    model="claude-opus-4-8",
    max_tokens=1024,
    messages=[
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": image_media_type,
                        "data": image_data,
                    },
                },
                {"type": "text", "text": "What is in the above image?"},
            ],
        }
    ],
)
print(message)

# 选项 2: URL 引用图像
message_from_url = anthropic.Anthropic().messages.create(
    model="claude-opus-4-8",
    max_tokens=1024,
    messages=[
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "url",
                        "url": "https://upload.wikimedia.org/wikipedia/commons/a/a7/Camponotus_flavomarginatus_ant.jpg",
                    },
                },
                {"type": "text", "text": "What is in the above image?"},
            ],
        }
    ],
)
print(message_from_url)
```

### 响应输出

```json
{
  "id": "msg_01EcyWo6m4hyW8KHs2y2pei5",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "This image shows an ant, specifically a close-up view of an ant. The ant is shown in detail, with its distinct head, antennae, and legs clearly visible. The image is focused on capturing the intricate details and features of the ant, likely taken with a macro lens to get an extreme close-up perspective."
    }
  ],
  "model": "claude-opus-4-8",
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 1551,
    "output_tokens": 71
  }
}
```

---

## 下一步

### 扩展阅读
1. **Stop Reasons and Fallback** — 处理每个 `stop_reason` 值并决定响应结束时的操作
2. **Tool Use with Claude** — 让 Claude 在 Messages API 中调用外部服务和 API
3. **Computer Use Tool** — 使用 Messages API 控制桌面计算机环境
4. **Structured Outputs** — 从 Claude 获取保证的、经模式验证的 JSON 输出
5. **Task Budgets** — 使用 `output_config.task_budget` 为完整的 Agent 循环设置建议性 Token 预算

---

**文档提取时间**: 2026-06-25  
**页面标题**: Using the Messages API - Claude API Docs  
**字符数**: 7448
