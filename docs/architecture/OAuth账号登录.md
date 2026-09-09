# Black God OAuth 账号登录

2026-09-09。当前包含 OpenRouter PKCE，以及 Kimi Code、xAI/Grok、MiniMax 两个区域的设备授权兼容适配。下方保留首轮记录并说明新增实现。

## 客户操作

我的 → 神枢连接 → 使用OpenRouter账号登录 → 官方页面完成登录和授权 → 自动关闭授权窗口并回到Black God → 获取模型列表 → 选择模型并保存使用。

客户不需要复制API Key。OpenRouter的OAuth流程返回用户控制的API Key，而非具有refresh token的短期访问令牌，所以本适配器不执行虚构的刷新流程。首轮只实现 OpenRouter；新增设备授权适配见本页后续章节。

## 实现

- NexusOAuth.swift：固定的服务商范围；系统安全随机数、S256 PKCE；回调严格验证协议、主机、端口、路径、state、唯一code及参数歧义；固定HTTPS换取端点，拒绝重定向，最多16KiB响应与4096字节凭据。错误只显示安全摘要，所有构建均不记录授权码或凭据。
- NexusOAuthCallback.swift：Network监听仅绑定127.0.0.1，使用动态端口，回调Host必须匹配localhost和端口；最多4个待处理连接、每个5秒、请求头最多8KiB、登录最多5分钟。无效请求不结束合法登录，合法结果只接受一次，随后释放监听；取消释放等待者。
- NexusOAuthLogin.swift：iOS SFSafariViewController登录窗口；回调自动关闭窗口；取消与generation隔离避免已取消/旧会话晚到结果写入。仅消费当前用户发起的会话，不读取其他应用凭据。
- NexusKeychain.swift：连接记录增加可选OAuth来源标记，selection允许为空以保存首次登录草稿。沿用connections_v2的原子Keychain记录，保存条目和密钥后才显示登录成功。草稿不自动替换当前模型；断开删除本机凭据并保留显式空值，避免回落旧密钥。远端撤销使用官方管理页，界面不把本机删除称为远端撤销。
- APIConfigView.swift：OAuth入口、浏览器取消、登录状态、自动获取模型列表、独立连接与模型选择。OAuth成功后隐藏手填密钥区域。模型列表失败保留已保存的登录，允许稍后重试；不自动发起计费推理测试。

Info.plist只增加NSAllowsLocalNetworking以支持本机回调，外部模型与换取端点仍固定或校验为HTTPS。尚未配置公开HTTPS回调域名，因此服务商授权页可能用localhost端口作为应用标识；这是本地开发接入阶段的明确边界。

## 验证与限制

本机回调、状态机与交换测试使用合成授权码和模拟服务端凭据，不等于真实账号授权成功。浏览器界面测试只打开官方登录流程并取消，不提交账号密码、授权同意或计费请求。本轮184项iOS单元回归通过。修复Safari关闭连带退出连接页的问题后，最终13项OAuth单元+1项界面复测通过；共185个不同iOS用例。登录入口截图已目视检查。

尚待真实账号端到端授权、真机前后台/系统浏览器跳转、厂商远端撤销后的反馈与公开回调品牌配置。本次不宣称所有厂商OAuth已实现。

[官方OpenRouter OAuth PKCE流程](https://openrouter.ai/docs/guides/overview/auth/oauth)


## 第二轮：多厂商设备授权与刷新

新增 Kimi Code、xAI/Grok、MiniMax 国际区、MiniMax 中国区四条 OAuth 兼容路线。连同 OpenRouter，共五个账号登录入口；配置预设共十六条，包含同一家厂商的 API Key/OAuth 或区域变体，不代表十六家独立厂商。

| 路线 | 授权服务 | 推理接口及认证 | 授权身份 |
| --- | --- | --- | --- |
| Kimi Code | auth.kimi.com/api/oauth | api.kimi.com/coding/v1/chat/completions，Bearer | Kimi Code 公共客户端 |
| xAI / Grok | auth.x.ai/oauth2 | api.x.ai/v1/chat/completions，Bearer | Grok CLI 公共客户端 |
| MiniMax 国际区 | account.minimax.io/oauth2 | api.minimax.io/anthropic/v1/messages，x-api-key | MiniMax CLI 公共客户端 |
| MiniMax 中国区 | account.minimaxi.com/oauth2 | api.minimaxi.com/anthropic/v1/messages，x-api-key | MiniMax CLI 公共客户端 |

上述兼容路线使用公开源码中的 public client ID，没有 client secret。Black God 尚未拥有各厂商独立登记的 OAuth 应用身份；授权页面可能显示对应 CLI 的名称，应用入口已明确提示。是否允许该账号调用模型取决于厂商权限、订阅及客户端政策。匿名握手成功不等于第三方集成获正式认可，也不等于推理已开通。没有读取其他应用凭据，没有伪装 CLI User-Agent 或绕过账号白名单。

Kimi 不额外请求 scope；Grok 使用其公开设备授权流程的 scope；MiniMax 使用 openid/profile/coding_plan、S256 PKCE 和 state。MiniMax expired_in 是 Unix 毫秒绝对时间，interval 是毫秒；Kimi/Grok expires_in 和 interval 是秒。设备轮询使用标准 device_code grant URN，但 MiniMax 传 user_code 与 code_verifier，Kimi/Grok 传 device_code，不能混用旧的 MiniMax user_code grant 路线。

### 凭据生命周期

- 新增 NexusDeviceOAuth.swift：固定每家授权/令牌地址，授权页面按域名和区域限定，严格验证 PKCE/state、数值单位、凭据类型与换行、过期时间、resource_url。最多接收 32 KiB 响应，拒绝 HTTP 重定向，错误不包含返回正文或凭据。
- 浏览器关闭后设备流程继续等待，用户可重新打开授权页或明确取消。取消、超时与晚到结果隔离；授权成功后只保存当前登录。最长等待十五分钟，且不超过服务商给定寿命；每次网络请求另有超时。
- access token、refresh token、过期时间、服务商、登录会话 ID 原子保存在本机 Keychain。连接快照仅记录会话 ID，任务不因重新授权而悄悄换成另一个账号。
- 新增 NexusOAuthCredentials.swift：发起聊天、原生工具回合或模型列表请求前检查凭据，剩余不足两分钟则刷新；同一登录的并发请求合并成一次刷新。按旧值比较后替换，断开或重新授权后旧刷新不能恢复凭据；表单中的旧令牌也不能覆盖刷新结果。
- 刷新被明确拒绝时清除对应旧登录；服务端故障保留凭据供重试。取消的调用不会继续发送推理请求；共享刷新可完成以保存服务商已轮换的凭据。不会因推理 HTTP 401 自动重放有费用的模型请求。
- 登录后自动读取模型列表；不支持列表的账号可以填写服务商给定的模型 ID。测试聊天、测试工具均由用户明确点击后执行。

### 验证范围

2026-09-09，在本机分别向四条官方设备授权入口发起匿名请求，均返回 HTTP 200。Kimi/Grok 返回预期的官方授权域名；MiniMax 中国区/国际区返回各自区域的官方授权域名且 state 匹配。未保存或输出设备授权码，没有输入账号或同意授权，没有发起计费推理。

206 项全量 iOS 单元回归通过。最后增加传输边界用例，36 项认证专项与 2 项界面复测通过；累计 207 个不同单元用例和 2 个不同界面用例通过。用例包含协议字段、时间单位、域名/区域隔离、异常凭据、轮询与退避、刷新和并发合并、注销/重新登录竞态、三种客户端入口使用新令牌，以及取消后不发模型请求。

真实账号从授权、选择模型、完成回答、工具调用到令牌到期刷新的端到端流程仍未验收。真机前后台、网络切换、远端撤销和长期运行也未验收；这属于兼容集成开发阶段，不宣称已达到工业级或 ASI。

### 其他大厂现状

OpenAI、Anthropic、Google、阿里、字节、DeepSeek、智谱、腾讯等仍保留已实现的 API Key 配置。OpenAI/Codex 账号登录依赖专用 Responses/账号链路，本轮未接入；Google 移动端需要合适的 OAuth 客户端配置，不照搬桌面 CLI 回调；Claude.ai 订阅凭据不能作为第三方应用通用 API 登录；Qwen 官方文档已将旧 Qwen OAuth 标记为停用。本轮没有把这些未完成路线显示成可用的 OAuth 按钮。

### 参考依据

- [Kimi CLI 官方 OAuth 实现](https://github.com/MoonshotAI/kimi-cli/blob/main/src/kimi_cli/auth/oauth.py)
- [xAI 官方 OpenID 元数据](https://auth.x.ai/.well-known/openid-configuration)
- [xAI Grok 官方开源仓库](https://github.com/xai-org/grok-build)
- [MiniMax 官方 CLI OAuth](https://github.com/MiniMax-AI/cli/blob/main/src/auth/oauth.ts)、[刷新](https://github.com/MiniMax-AI/cli/blob/main/src/auth/refresh.ts)、[推理路由](https://github.com/MiniMax-AI/cli/blob/main/src/client/endpoints.ts)
- [OpenAI Codex app-server 登录接口](https://learn.chatgpt.com/docs/app-server)
- [Google 移动 OAuth 回调迁移](https://developers.google.com/identity/protocols/oauth2/resources/loopback-migration)
- [Claude Code 法律与合规说明](https://code.claude.com/docs/en/legal-and-compliance)
- [Qwen Code 当前认证说明](https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/)


## 第三轮：Claude 与内容发送许可

Claude 官方 API 配置支持多工作区密钥所需的 anthropic-workspace-id。workspace 字段按 Anthropic 协议、wrkspc_ 前缀、ASCII 字符和长度校验，不允许通过头字段注入。Claude.ai 订阅授权不转用为 Black God 原生登录；官方文档允许未修改 Claude Code 的特定托管场景，不等于允许客户端复用订阅令牌，本项目没有嵌入该二进制。

NexusDataConsent 以连接身份、协议、目标 URL、OAuth 会话和工作区生成独立许可键。OAuth 或 API Key 保存不自动授权发送内容。NexusClient 在聊天与原生工具回合入口、刷新凭据之前强制验证；模型发现不发送对话，所以不要求内容许可。撤销会阻止后续请求，但不能撤回已发送的数据。

本轮 213 个单元用例和 2 个不同 UI 用例通过；真实付费推理、真实账号授权及服务商远端撤销仍未验证。
