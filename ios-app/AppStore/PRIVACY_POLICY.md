# 隐私政策 / Privacy Policy

**神枢 Black God（Black God Nexus）**

更新日期 / Last updated: 2026-09-08

## 中文

### 1. 适用范围

本政策说明神枢 iPhone App 如何处理数据。App 无独立账号系统，也未内置广告、行为统计或第三方崩溃上报 SDK。AI 请求由设备直接发送至你选择的模型服务商，当前客户端没有开发者运营的请求中转服务。

本地存储不等于离线处理：使用 AI 功能时，你的输入和相关上下文会离开设备。

### 2. 设备上保存什么

- 各服务商的 API Key、所选模型和数据共享选择保存在 iOS Keychain 中。新写入的条目采用解锁时可用、限本设备的保护属性。Key 在发送请求时作为身份凭据传给对应服务商；此设置无法删除此前创建的备份或外部副本。
- 新记忆由你手动收藏，可能包含输入、模型结果或其他你选择保存的文字及时间，用于后续任务检索。最多保存 200 条，每条最多 4,000 字符。旧版本已保存的记忆可能保留至删除。匹配的已收藏记忆可能加入后续 AI 请求，包括你切换服务商后的请求。
- 本机任务历史最多保存最近 50 次任务，包括目标、步骤、工具结果和最终输出。旧版本的运行评估记录也可能仍保留，其中包含任务文本、状态标记、时间和延迟，上限为 1,000 条。任务检查点及 App 工作区内的工具文件也保存在设备上。
- 当前聊天界面保留会话内存状态；任务内容另存为上述历史，不应把关闭聊天页理解为删除这些内容。后续 AI 请求可包含最近最多 6 条对话，并受文本长度上限约束。
- App 没有自行实现跨设备同步。系统备份、设备迁移和 Keychain 行为由 iOS 及你的设备设置管理，本政策不承诺这些数据排除在系统备份之外。

### 3. 哪些数据会发送给谁

在「我的 → API 配置」选择模型后，可查看对应服务商并打开「AI 数据共享」开关，再点「保存」。未同意该服务商的数据共享时，App 不向其发送 AI 请求。

同意后，使用该服务商的 AI 功能会发送输入、最近最多 6 条对话（受文本长度上限约束）、相关已收藏记忆、任务步骤及必要的任务上下文；多轮任务可能包含先前输出和工具结果。API Key 用于验证请求。服务商也会收到完成网络请求所需的信息，例如 IP 地址、请求时间、模型名称和请求头。用途为模型回复、任务处理及服务商的验证和运行服务。

| 服务商 | AI 接口 | 服务商的数据说明 |
|---|---|---|
| Anthropic | `https://api.anthropic.com` | [API 数据保留说明](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention) |
| OpenAI | `https://api.openai.com/v1` | [隐私政策及商业服务适用范围](https://openai.com/policies/privacy-policy/) |
| DeepSeek | `https://api.deepseek.com/v1` | [开放平台服务条款](https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html)、[隐私政策](https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html) |
| xAI | `https://api.x.ai/v1` | [API 企业客户数据说明](https://x.ai/legal/faq-enterprise) |

服务商处理、存储地点、保留期限及删除方式取决于其适用的 API 协议、账户方案和设置；个人聊天产品的政策不一定适用于 API。App 不承诺服务商零保留或不使用数据训练。使用前请查看你账户适用的数据条款。数据可能在你所在国家或地区以外处理。

开发者不通过本客户端接收或保存这些 AI 请求的服务端副本。打开政策、支持或其他外部网页时，该网站会按其自身政策处理访问数据。

### 4. 控制、保留与删除

- **撤回共享**：在「我的 → API 配置」选择相应服务商的模型，关闭「允许发送给…」并保存。撤回后新的 AI 请求会被阻止；已经发送的数据无法由 App 撤回。需要立即停止当前任务时，请先在对话页停止任务。
- **清除本地内容**：在「我的 → 清除全部数据」确认后，App 清除其 Keychain 条目、已收藏记忆、任务历史、运行记录、检查点和其管理的工作区内容，并重置当前会话。未设置过期时间的记忆没有固定的自动删除天数，受上述数量上限约束。你也可以在记忆及历史管理页面删除相应记录。
- **第三方副本与凭据**：清除本地数据不会删除服务商保存的请求、撤销服务商账户或吊销 API Key。请到相应服务商管理凭据并申请删除数据。你另行复制、导出或备份的内容也需要分别处理。
- **卸载**：不要仅依赖卸载来撤销凭据或清除 Keychain。需要删除本地信息时请先使用 App 内的清除功能。

### 5. 主动分享、支持、儿童与政策更新

你主动使用结果分享功能时，所选内容会交给你在系统分享界面选择的 App 或接收方，由其按自身规则处理。

可通过 [项目支持页面](https://github.com/zhumingjie0223-cyber/Black-God/issues) 联系维护者。你主动提交的用户名、问题描述及附件会被用于处理问题；GitHub Issues 是公开页面，请勿提交 API Key 或私密聊天内容。支持记录由 GitHub 托管，你可以管理自己的内容或联系维护者请求删除其可控制的记录。

App 面向使用模型服务商 API 的用户，并非专为儿童设计。使用者还须满足所选服务商的年龄及账户要求。

政策变化会更新本文件及日期。新增服务商或改变数据用途时，应在相关使用前提供更新的说明和所需选择。

## English

### 1. Scope

This policy describes data handling in the Black God Nexus iPhone app. The app has no separate account system and embeds no advertising, behavioral analytics, or third-party crash-reporting SDK. AI requests go directly from your device to your selected model provider; the current client uses no developer-operated request relay.

Local storage does not mean offline processing. AI features send your input and relevant context off the device.

### 2. Data stored on your device

- Provider API keys, the selected model, and sharing choices are stored in iOS Keychain. New writes use protection that makes them available while the device is unlocked and restricts them to that device. A key is sent to its corresponding provider to authenticate requests. This setting cannot remove older backups or external copies.
- You manually save new memory, which may contain input, model results, other text you choose, and timestamps for retrieval in later tasks. Up to 200 entries are kept, each limited to 4,000 characters. Memory from earlier versions may remain until deleted. Matching saved memory may be included in future AI requests, including after you switch providers.
- Local task history retains up to the latest 50 tasks, including goals, steps, tool results, and final output. Up to 1,000 evaluation records from earlier versions may also remain, containing task text, status flags, timestamps, and latency. Task checkpoints and app workspace files are also stored locally.
- The chat screen maintains session state in memory; task content is separately saved in history. Closing the chat does not delete that history. Later AI requests may include up to the six most recent conversation messages, subject to text-length limits.
- The app implements no cross-device sync. System backups, device migration, and Keychain behavior depend on iOS and your settings. We do not promise that this data is excluded from system backups.

### 3. Data sent to model providers

Under Me → API configuration (「我的 → API 配置」), choose a model, review its provider, enable its AI data sharing switch, and save. The app blocks AI requests to a provider until you have agreed to share data with it.

When you then use that provider, requests include your input, up to six recent conversation messages within text-length limits, relevant saved memory, task steps, and necessary task context. Multi-step tasks may include earlier outputs and tool results. Your API key authenticates the request. The provider also receives network information needed for the request, such as your IP address, request time, model name, and headers. This supports model responses, task processing, authentication, and service operation.

| Provider | AI endpoint | Provider data information |
|---|---|---|
| Anthropic | `https://api.anthropic.com` | [API data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention) |
| OpenAI | `https://api.openai.com/v1` | [Privacy policy and business-service scope](https://openai.com/policies/privacy-policy/) |
| DeepSeek | `https://api.deepseek.com/v1` | [Open Platform terms](https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html), [privacy policy](https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html?os=___) |
| xAI | `https://api.x.ai/v1` | [Enterprise/API data FAQ](https://x.ai/legal/faq-enterprise) |

Provider processing, storage locations, retention, and deletion depend on the applicable API agreement, account plan, and settings. Consumer chat policies may not apply to APIs. The app does not promise zero provider retention or exclusion from training. Review the terms that apply to your account. Processing may occur outside your country or region.

The developer does not receive or store server-side copies of these AI requests through this client. Visiting external policy or support pages is subject to those websites' own data practices.

### 4. Choices, retention, and deletion

- **Withdraw sharing:** Select the provider's model under 「我的 → API 配置」, disable 「允许发送给…」, and save. This blocks new AI requests; data already sent cannot be recalled by the app. Stop an active task in Chat first if you need it to stop immediately.
- **Clear local data:** Choose 「我的 → 清除全部数据」 and confirm. The app clears its Keychain entries, saved memory, task history, run records, checkpoints, and app-managed workspace, then resets the current conversation. Memory without an expiry date has no fixed automatic deletion period; the count limit above applies. You can also delete records from the memory and history management screens.
- **Provider copies and keys:** Clearing local data does not erase provider-held requests, close provider accounts, or revoke keys. Manage credentials and data-deletion requests with the relevant provider. Copies, exports, and backups you created must be handled separately.
- **Uninstalling:** Do not rely on uninstalling to revoke credentials or erase Keychain. Use the in-app clearing function first when you need to remove local information.

### 5. Sharing, support, children, and updates

If you choose to share a result, the selected content is handed to the app or recipient you choose in the system share sheet, subject to that recipient’s own practices.

Contact the maintainers through [project support](https://github.com/zhumingjie0223-cyber/Black-God/issues). Usernames, descriptions, and attachments you submit are used to address your request. GitHub Issues are public; never post API keys or private conversations. GitHub hosts support records; manage your own content there or ask the maintainers to remove records under their control.

The app is intended for users of model-provider APIs and is not specifically designed for children. Users must also meet the selected provider's age and account requirements.

We update this document and its date when practices change. New providers or new uses of data should be explained, with the required choices, before the affected use.
