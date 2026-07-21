# Black God 私人版回溯与升级清单

更新时间：2026-06-28 18:45  
范围：只回溯 `/var/minis/shared/blackgod` 私人版，不以公开版为准，不把公开版逻辑反推私人版。

---

## 0. 这次重新理解后的结论

私人版不是空壳，能跑、能对话、核心文件也在。真正的问题不是“有没有代码”，而是：

1. **当前线上入口实际跑的是 `server/agent_kernel_v4.py` 这个自包含单体内核。**
2. `server/core/` 里很多高级模块已经写好，但没有接进主执行链。
3. Web / iOS 已经有 API 填写入口，但目前只是单 Provider：Base URL + API Key + Model。
4. 公开版、Cloudflare Demo、账号包装已经做过，但那是对外展示；私人版升级不能拿公开版反推。
5. 后续要做的是：先把私人版现有功能接稳，再升级接口系统、Provider 系统、Key 池、成本级联、真实对话引擎、画像、记忆和技能闭环。

一句话：**私人版当前是“可运行单体 v4 + 一堆未接线高级模块”，下一步是工程收口，不是继续写宣传。**

---

## 1. 已确认做好的部分

### 1.1 私人版仓库存在且可运行

位置：`/var/minis/shared/blackgod`  
当前分支：`private`  
最新提交：`c25de3d feat(agent): 完整 Agent 内置系统 v4.0`

验证结果：

- `python3 server/server.py` 能启动。
- `/api/health` 返回 200。
- `/api/stats` 返回 200。
- `/api/capabilities` 返回 200。
- `/api/chat` 真实可用，测试消息“只回复两个字：在的”返回“在的”。

当前运行入口：

```text
server/server.py
  -> import agent_kernel_v4.start_server
  -> HTTP server on BG_PORT / 8765
```

### 1.2 v4 主内核已做好的能力

文件：`server/agent_kernel_v4.py`

已具备：

- 内嵌人格宪法 `CONSTITUTION`
- 内嵌技能字典 `SKILLS`，共 14 个
- 内嵌工具定义 `TOOLS`，共 10 个
- SQLite 记忆系统：global / daily / session / tasks
- Agent Loop：模型调用 + tools + 多步循环 + 首次失败降级
- REST API：
  - `GET /api/health`
  - `GET /api/stats`
  - `GET /api/tasks`
  - `GET /api/memory`
  - `GET /api/capabilities`
  - `GET /api/tool-matrix`
  - `GET /api/preferences`
  - `GET /api/events`
  - `POST /api/chat`
  - `POST /api/confirm`
  - `POST /api/memory/save`
  - `POST /api/preferences`
  - `POST /api/tool/execute`

实测：这些基础 API 中 health/stats/capabilities/chat 已通。

### 1.3 高级模块文件已存在，并且语法全部通过

`server/core/*.py` 共 33 个核心模块。语法检查：`OK=35 BAD=0`。

代表模块：

- `onboarding.py`：412 行
- `self_evolving.py`：362 行
- `cloudflare_mcp.py`：346 行
- `multi_agent.py`：329 行
- `adaptive_reasoning.py`：287 行
- `skill_index.py`：276 行
- `user_profile_engine.py`：270 行
- `agent_kernel.py`：233 行
- `gateway.py`：224 行
- `cost_engine.py`：203 行
- `real_dialog_engine.py`：196 行
- `llm_adapter.py`：192 行
- `memory_integrator.py`：132 行
- `real_backends.py`：135 行

这说明：**不是没写代码，是很多代码没有接线。**

### 1.4 API 填写入口已经有基础版

Web：`web/index.html`

已有入口：

```text
我的 -> 接口设置
Base URL
API Key
默认模型 ID
保存并测试连接
```

当前保存字段：

```text
api_base
api_key
api_model
```

iOS：`ios-app/APIConfigView.swift`

已有字段：

```swift
@AppStorage("api_base") var apiBase
@AppStorage("api_key") var apiKey
@AppStorage("api_model") var apiModel
```

当前预设：

- DeepSeek
- 火山方舟
- OpenAI
- Claude 中转

### 1.5 新增的省 Key / 网关相关模块已经放进私人版

当前 git 状态显示已新增但未提交：

- `server/core/cost_engine.py`
- `server/core/demo.py`
- `server/core/gateway.py`
- `server/core/llm_adapter.py`
- `server/core/real_backends.py`

这些模块之前已经实测过：

- demo 模式可跑
- 成本级联演示节省约 98.8%
- `llm_adapter.py` 接入 `apiclaude.cc/v1` + `gpt-5.5` 实测可用
- Claude OAuth 官方 token 也曾单独验证过可用，但这条后续另谈

---

## 2. 已做但没接完整的部分

### 2.1 `server/core/` 高级模块未接入 v4 主内核

证据：`server/agent_kernel_v4.py` imports 只有：

```python
import json, os, re, time, sqlite3, hashlib, subprocess, urllib.request
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, List, Any
from http.server import HTTPServer, BaseHTTPRequestHandler
```

没有 import：

- `real_dialog_engine`
- `cost_engine`
- `gateway`
- `llm_adapter`
- `real_backends`
- `multi_agent`
- `adaptive_reasoning`
- `self_evolving`
- `onboarding`
- `user_profile_engine`
- `memory_integrator`
- `skill_index`

结论：这些模块目前更多是“已写好、可接入”，不是“正在主链路运行”。

### 2.2 成本级联引擎已写，但主链路还没走它

已存在：

- `cost_engine.py`
- `gateway.py`
- `real_backends.py`
- `llm_adapter.py`

未完成：

- `AgentLoop.run()` 还没有先走 L0-L6 成本级联。
- `_call_model()` 仍然直接请求 `base_url/chat/completions`。
- 缓存、记忆复用、规则引擎还没有成为模型调用前置层。

### 2.3 API Provider 填写面还只是单接口，不是 Provider 系统

现在 Web / iOS 都只能填：

```text
Base URL + API Key + Model
```

缺少：

- 多 Provider 列表
- Provider 类型：OpenAI-compatible / Anthropic OAuth / Gemini / Custom
- 质量优先 / 稳定优先 / 低成本优先
- 默认 Provider 设置
- 测试连接状态
- token 遮蔽显示
- Provider 健康状态
- 多 key 池
- 本地 secret store

### 2.4 前端调用了后端不存在的接口

Web 前端调用：

```text
/api/profile
/api/push/subscribe
/api/push/unsubscribe
```

后端当前返回：

```text
/api/profile -> 404
/api/push/subscribe -> 404
/api/push/unsubscribe -> 404
```

结论：前端部分交互会“看起来有按钮”，但后端没接。

### 2.5 本地画像 / onboarding 已有模块，但未接入

存在：

- `server/core/onboarding.py`
- `server/core/user_profile_engine.py`

未完成：

- `/api/profile` 没有接到 `user_profile_engine`
- 首次引导数据还没入主内核记忆上下文
- “授权多少懂多少 / 未授权陌生人模式”还停在设计层

### 2.6 真对话引擎已存在，但未接入

存在：`server/core/real_dialog_engine.py`

功能定位：

- 情绪识别
- 语气切换
- 人格状态变化
- 更像真人的对话延续

未完成：

- v4 主内核没有调用它
- 现在人格主要是静态 system prompt 注入

---

## 3. 做好了，可以继续升级的部分

### 3.1 v4 主内核可以作为稳定底座升级

优点：

- 单文件自包含，启动简单
- API 基础可用
- Agent Loop 已跑通
- SQLite 记忆可用
- 对外 HTTP 路由清晰

升级方向：

1. 不推翻 v4。
2. 用 v4 当稳定入口。
3. 逐步把 core 模块接成插件。
4. 每接一个模块做一次冒烟测试。

### 3.2 API 填写面可以直接升级成 Provider 面板

现有入口已经在 Web / iOS 里，不需要重做页面。

升级内容：

- 保留单接口模式作为兼容
- 增加 Provider 列表
- 增加“测试连接”
- 增加“设为默认”
- 增加本地保存与遮蔽显示

建议先做 Web，再同步 iOS。

### 3.3 `llm_adapter.py` 可以作为统一模型适配地基

已具备：

- 统一 `llm(messages)->str`
- 支持 OpenAI-compatible 格式
- 不打印密钥
- 能识别错误

升级方向：

- 增加 Anthropic OAuth Provider，但这条按你要求后面再谈
- 增加 ProviderRegistry
- 增加 key pool
- 增加健康检查

### 3.4 `cost_engine.py + gateway.py` 可以接进模型调用前置层

已验证 demo 能跑，适合作为：

```text
用户请求 -> 本地规则/缓存/记忆/技能 -> 真模型
```

升级优先级高，因为它直接对应 Black God 的核心价值：**越用越省**。

### 3.5 `memory_integrator.py / self_evolving.py / skill_index.py` 可以形成“越用越强”闭环

这几个模块是 Black God 私人版的长期护城河：

- 记忆压缩
- 技能索引
- 经验复用
- 自动沉淀

但必须等 Provider/API 基础稳定后再接，否则调试困难。

---

## 4. 没做好的部分，以及怎么补

### P0：先补 API Provider 填写面

原因：

- 这是私人版继续升级的入口。
- 没有稳定 Provider 配置，后面的成本级联、Claude Max、key 池都无处落地。

要做：

1. Web `接口设置` 改成 Provider 面板。
2. iOS `APIConfigView.swift` 同步升级。
3. 后端新增 Provider 配置 API：

```text
GET  /api/providers
POST /api/providers/save
POST /api/providers/test
POST /api/providers/default
GET  /api/providers/status
```

4. 配置只写本地私密文件，不进 git。
5. token 只写入，不回显。

验收：

- 能添加 Provider。
- 能测试连接。
- 能设为默认。
- `/api/chat` 能读取默认 Provider。

### P1：修前端缺失接口

要补：

```text
GET  /api/profile
POST /api/profile
POST /api/push/subscribe
POST /api/push/unsubscribe
```

说明：

- `/api/profile` 接 onboarding / user_profile_engine。
- push 先做本地订阅存储，不急着发真实 WebPush。

验收：

- Web 不再 404。
- “我的 / 本地画像 / 推送”有真实返回。

### P2：接成本级联引擎

要改：

- `AgentLoop.run()` 前置成本引擎。
- 命中 L0-L4 时直接返回。
- miss 时再进原 Agent Loop。

风险：

- 规则误命中。
- 缓存过期。

控制：

- 先只对明确安全请求启用。
- 敏感/复杂请求直接 miss 到模型。

### P3：接真实对话引擎

要改：

- 用户消息进入 `real_dialog_engine` 做情绪/意图识别。
- 生成动态 system hint。
- 和静态 CONSTITUTION 合并。

验收：

- 用户催促时变短。
- 用户说累/急时语气变化。
- 不影响工具调用。

### P4：接本地画像与 onboarding

要改：

- `/api/profile` 真实读写。
- 首次引导结果注入记忆。
- 未授权时陌生人模式。

验收：

- 第一次填写偏好。
- 后续对话能用偏好。
- 取消授权时不假装了解。

### P5：接技能系统与自进化

要改：

- `skill_index.py` 动态扫描技能。
- `self_evolving.py` 沉淀任务经验。
- 高频稳定任务转技能。

验收：

- 完成任务后生成经验。
- 相似任务复用经验。
- 低质量技能不入库。

---

## 5. 明确不要再犯的错误

1. 不再把 Black God 的私人能力拿去补别的项目。
2. 不再用公开版状态判断私人版状态。
3. 不再把文档宣传当成功能完成。
4. 不再把“理论能做”写成“已经能用”。
5. 不再输出真实 token、服务器密码、sessionKey。
6. 不再未确认就改主内核或推送。

---

## 6. 推荐升级顺序

### 第一步：Provider/API 填写面

这是当前最该做的，因为它是后面所有接口能力的入口。

交付物：

```text
server/core/provider_registry.py
server/core/secret_store.py
server/core/provider_tester.py
web/index.html Provider 设置面
ios-app/APIConfigView.swift Provider 设置面
agent_kernel_v4.py provider读取逻辑
```

### 第二步：补 `/api/profile` 和 push 404

先让前后端对齐。

### 第三步：把成本级联接入 `AgentLoop.run()`

让“越用越省”成为真实运行路径。

### 第四步：接真实对话引擎

让私人版人格从静态 prompt 变成动态行为。

### 第五步：接画像、记忆、自进化、技能闭环

让“越用越懂你、越用越强”落地。

---

## 7. 当前可以立刻执行的最小改造包

如果下一步你确认执行，我建议只动这些，范围最小：

```text
新增：server/core/secret_store.py
新增：server/core/provider_registry.py
新增：server/core/provider_tester.py
修改：server/agent_kernel_v4.py
修改：web/index.html
修改：ios-app/APIConfigView.swift
修改：ios-app/ChatViewModel.swift
```

目标：

- 支持多个 API Provider 填写。
- 支持连接测试。
- 支持默认 Provider。
- token 私密保存，不回显。
- 不接 Claude Max 逆向细节，先保留 Provider 类型入口。
- 不碰公开版。

---

## 8. 当前状态总表

| 模块 | 状态 | 证据 | 下一步 |
|---|---|---|---|
| v4 主内核 | 已可运行 | health/stats/chat 通 | 作为底座升级 |
| Web 前端 | 已可用 | index.html 1295 行 | API 设置面升级 |
| iOS API 配置页 | 有基础版 | APIConfigView.swift | 升级 Provider 面板 |
| API Provider 系统 | 未完成 | 只有单 base/key/model | P0 新增 |
| 成本级联 | 已写未接 | cost_engine/gateway 存在 | P2 接入 |
| 真实对话引擎 | 已写未接 | real_dialog_engine 存在 | P3 接入 |
| 本地画像 | 已写未接 | onboarding/user_profile_engine 存在 | P4 接入 |
| push 接口 | 未完成 | 404 | P1 补 |
| `/api/profile` | 未完成 | 404 | P1 补 |
| 自进化/技能闭环 | 已写未接 | self_evolving/skill_index | P5 接入 |
| 公开版 | 已独立完成 | BlackGod-B/Blackgod | 不反推私人版 |

---

## 9. 结论

私人版值得继续做，但必须按工程顺序收口：

1. **先做 API Provider 填写面**，让接口配置成为真实系统。
2. **再补前后端缺口**，把 404 清掉。
3. **再接成本级联**，把省 Key 变成真实运行路径。
4. **再接私人动态人格和本地画像**，让它真正越用越懂你。
5. **最后接自进化和技能闭环**，让它越用越强。

现在最小、最稳、最该做的一步就是：

```text
私人版 Provider/API 填写系统 P0
```

这一步完成后，后面的 Claude Max、key 池、多模型、成本级联才有干净入口。
