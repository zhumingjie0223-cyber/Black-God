# Minis 模型接入与 Black God 开发对照

检查日期：2026-09-09。参考仓库 `/Users/aquan/Downloads/OpenMinis`，提交 `4ef29002e88db1e20e462ec2ff46916e8a7dcb45`；参考仓库未修改。本轮以开发和联调为目标，没有提交上架。

## Minis 实际实现

- `src/ios/Providers/ProviderInstance.swift`：连接实例与模型分离，同一种服务商允许多账号、自定义地址及认证方式。
- `src/ios/Providers/LLMProvider.swift`：普通和流式消息的统一接口。
- `src/ios/Providers/LLMProviderFactory.swift`：依据连接实例创建 Anthropic、Gemini、OpenAI、OpenAI Responses、OpenRouter、xAI、Kimi 等适配器。具体产品还包含额外请求头、Azure 与 OAuth 分支。
- `src/ios/Providers/ProviderConfigStore.swift` 与各家的 `*ModelsAPI.swift`：获取、缓存模型与配置；读取实例关联的钥匙串凭据。
- `src/ios/Providers/ModelGroupRouter.swift`：模型组的故障切换或负载分配。
- `src/ios/NativeOffloads/ModelUseOffloadBridge.swift`：将脚本侧 model-use 请求交给宿主模型客户端；模型本身并不运行在 iSH 内。

因此可借鉴的是“连接实例—协议适配—模型选择—Agent工具回合”的结构；只接入 Linux 或增加服务商名称都不足以得到这些能力。

## Black God 本轮对应实现

| 能力 | 当前实现 |
|---|---|
| 多家入口 | OpenAI、Anthropic、Gemini、百炼、方舟、DeepSeek、智谱、Moonshot、MiniMax、腾讯混元、xAI，共11家；另有自定义接口 |
| 独立连接 | 可保存同家多个账号及不同地址；连接ID对应独立凭据；单次钥匙串写入原子保存选择、模型和密钥 |
| 模型选择 | 从模型列表接口读取，保留手动输入；预设不编造或固定新模型ID |
| 四类协议 | Anthropic Messages、OpenAI Chat Completions、OpenAI Responses、Gemini原生 generateContent |
| 文本和工具回合 | 前两者支持文本SSE；Responses/Gemini当前使用完整JSON；四者均接入函数调用及真实本机工具回传 |
| 必要上下文 | 回传不透明调用ID、Gemini thoughtSignature、Responses encrypted_content；不在UI展示或持久化 |
| 任务配置一致性 | 一次任务固定地址、模型、协议和密钥；设置切换不影响旧任务 |
| 证据和复核 | 长输出保留首尾，复核保留最近纠错证据；有未恢复工具失败时不标为已验证 |

模型组自动故障切换、负载分配、OAuth、Azure专有认证以及各厂商完整多模态能力不在本轮已实现清单中。不会在接口失败时静默将对话转发给其他服务商。

## 官方协议依据

- [OpenAI函数调用](https://developers.openai.com/api/docs/guides/function-calling)：Responses工具定义、call_id与function_call_output配对。
- [OpenAI推理模型](https://developers.openai.com/api/docs/guides/reasoning)：必要推理项目回传；请求关闭store并申请加密上下文。
- [Gemini generateContent](https://ai.google.dev/api/generate-content) 与 [模型列表](https://ai.google.dev/api/models)：原生请求、候选结束原因、模型查询。
- [Gemini函数调用](https://ai.google.dev/gemini-api/docs/function-calling)：函数声明、函数响应与签名回传。
- [百炼兼容接口](https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope)：业务空间和地域对应BASE_URL，不自动替用户猜地址。
- [Kimi快速开始](https://platform.kimi.com/docs/get-api-key)、[智谱模型](https://docs.bigmodel.cn/cn/guide/start/model-overview)、[MiniMax OpenAI接口](https://platform.minimaxi.com/docs/api-reference/text-openai-api)、[混元兼容接口](https://cloud.tencent.cn/document/product/1729/111007)。
- 火山方舟接入参考本地Minis模型资料及官方文档入口 https://www.volcengine.com/docs/82379/1494384；本轮网页工具未能读取该页，不将其算作实网请求验证。

## 验证边界

自动化传输测试使用隔离的URLProtocol响应，并实际经过URLSession、协议编码/解析、工具执行和结果回传。它证明代码路径，不证明服务商账户已认证成功。真实API仍需要在应用内配置对应密钥；不要将密钥写进报告或聊天。模型列表可读不代表该账号有所有模型的推理或工具权限。

Linux工作区仍属实验能力。当前验证包括目录边界、系统文件写保护、取消、超时、清理、前后台和中断记录；共用客体内核的全面审计、硬磁盘配额、长期低内存压力与真实模型任务质量仍需进一步验证。

## 后续智能体源码研究

已经进一步检查 Hermes Agent 和开源 Codex，并完成复核后补充工具证据的纠错流程。具体提交、来源、测试和待实现项见同目录《智能体源码对照与验收路线.md》。
