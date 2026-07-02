# Claude 内部 API 文档（逆向工程）

## 基础信息

**Base URL**: `https://claude.ai`  
**认证方式**: Cookie `sessionKey=sk-ant-sid02-xxx`

---

## 1. 发送消息 API

### Endpoint
```
POST /api/organizations/{organization_id}/chat_conversations/{conversation_uuid}/completion
```

### Headers
```
Cookie: sessionKey=sk-ant-sid02-xxx
Content-Type: application/json
```

### Request Body
```json
{
  "prompt": "用户的消息内容",
  "timezone": "Asia/Shanghai",
  "attachments": [],
  "files": []
}
```

### Response (Server-Sent Events)
```
event: completion
data: {"completion": "回复内容片段1", "stop_reason": null}

event: completion  
data: {"completion": "回复内容片段2", "stop_reason": null}

event: completion
data: {"completion": "", "stop_reason": "stop_sequence"}
```

---

## 2. 创建新对话

### Endpoint
```
POST /api/organizations/{organization_id}/chat_conversations
```

### Request Body
```json
{
  "uuid": "生成的UUID",
  "name": ""
}
```

### Response
```json
{
  "uuid": "conversation-uuid",
  "name": "",
  "created_at": "2026-06-25T11:00:00.000Z",
  "updated_at": "2026-06-25T11:00:00.000Z"
}
```

---

## 3. 获取对话列表

### Endpoint
```
GET /api/organizations/{organization_id}/chat_conversations
```

### Response
```json
[
  {
    "uuid": "xxx",
    "name": "对话标题",
    "created_at": "2026-06-25T10:00:00.000Z",
    "updated_at": "2026-06-25T11:00:00.000Z"
  }
]
```

---

## 4. 获取组织信息

### Endpoint
```
GET /api/organizations
```

### Response
```json
[
  {
    "uuid": "0204faae-7e3a-4d10-9480-f00a73827ee5",
    "name": "Personal",
    "settings": {...}
  }
]
```

---

## 5. 获取账户信息

### Endpoint
```
GET /api/auth/current_account
```

### Response
```json
{
  "uuid": "6175e6cf-9cb6-4cb8-a6fb-df0d4dae0e2e",
  "email": "jjiebbay@gmail.com",
  "type": "individual",
  "capabilities": ["claude_pro"]
}
```

---

## 完整调用示例（Python）

```python
import requests
import uuid
import json

# 配置
SESSION_KEY = "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"
BASE_URL = "https://claude.ai"

headers = {
    "Cookie": f"sessionKey={SESSION_KEY}",
    "Content-Type": "application/json",
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
}

# 1. 获取组织ID
resp = requests.get(f"{BASE_URL}/api/organizations", headers=headers)
org_id = resp.json()[0]["uuid"]
print(f"组织ID: {org_id}")

# 2. 创建新对话
conv_uuid = str(uuid.uuid4())
resp = requests.post(
    f"{BASE_URL}/api/organizations/{org_id}/chat_conversations",
    headers=headers,
    json={"uuid": conv_uuid, "name": ""}
)
print(f"对话ID: {conv_uuid}")

# 3. 发送消息（流式响应）
resp = requests.post(
    f"{BASE_URL}/api/organizations/{org_id}/chat_conversations/{conv_uuid}/completion",
    headers=headers,
    json={
        "prompt": "1+1等于几",
        "timezone": "Asia/Shanghai",
        "attachments": [],
        "files": []
    },
    stream=True
)

# 4. 解析流式响应
for line in resp.iter_lines():
    if line:
        line = line.decode('utf-8')
        if line.startswith('data: '):
            data = json.loads(line[6:])
            if data.get('completion'):
                print(data['completion'], end='', flush=True)
            if data.get('stop_reason'):
                print(f"\n[结束原因: {data['stop_reason']}]")
                break
```

---

## 关键点

### ✅ 优势
- **绕过 API 限制**：用网页版额度，不消耗 API Credits
- **模型完整**：可用 Opus 3.5、Claude 3 等所有网页版模型
- **免费**：Pro/Max 订阅用户白嫖

### ⚠️ 限制
1. **需要有效 sessionKey**：从浏览器 Cookie 中提取
2. **sessionKey 会过期**：通常 30 天，需定期更新
3. **需要 organization_id**：每个账号不同，需先调用 `/api/organizations` 获取
4. **有 Cloudflare 保护**：需要真实浏览器 User-Agent 和 Cookie

### 🔒 获取 sessionKey 方法
1. 浏览器登录 claude.ai
2. 打开开发者工具 → Application/存储 → Cookies
3. 复制 `sessionKey` 的值（`sk-ant-sid02-xxx`）

---

## OpenAI 格式包装

```python
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)

@app.route('/v1/chat/completions', methods=['POST'])
def chat():
    data = request.json
    messages = data.get('messages', [])
    
    # 提取最后用户消息
    user_msg = next((m['content'] for m in reversed(messages) if m['role'] == 'user'), None)
    
    # 调用 Claude 内部 API
    session_key = "sk-ant-sid02-xxx"  # 你的 sessionKey
    org_id = "0204faae-7e3a-4d10-9480-f00a73827ee5"  # 你的组织ID
    conv_uuid = str(uuid.uuid4())
    
    # ... (完整代码如上)
    
    return jsonify({
        "choices": [{
            "message": {"role": "assistant", "content": response_text}
        }]
    })

if __name__ == '__main__':
    app.run(port=9003)
```

---

**文档生成时间**: 2026-06-25  
**来源**: 逆向工程 + 社区分享
