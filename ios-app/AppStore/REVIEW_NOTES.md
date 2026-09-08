# 审核备注 · 1.1.0（2）

以下为无凭据说明稿。提交人应先完成真实服务商测试，并在 App Store Connect 的私密审核备注或私密提交 JSON 中补充测试服务商、准确模型名称和有效 API Key。此文件不包含可登录凭据，不应连同本段作为完成稿提交。

## 可用的审核说明正文

Black God Nexus is a native iPhone AI client. Version 1.1.0 (build 2) has four screens: Chat, Workspace, History, and Me. The interface is primarily Simplified Chinese, with some English navigation/system text. It has no separate app account. AI use requires an internet connection and an API key for the selected provider. The app itself does not sell API credits or subscriptions; provider usage may be billed under the user's API account.

Test setup:

1. Open Me (「我的」), then API configuration (「API 配置」).
2. Select the model matching the supplied review credential and enter the key.
3. Read the provider-specific AI sharing disclosure, enable 「允许发送给…」, and tap Save (「保存」).
4. Return to Chat (「对话」) and ask a short question, such as “用三句话介绍番茄工作法”. A task plan, step progress, and tool activity appear while the result is prepared. Stop a task or continue from its saved checkpoint. The final result can be shared through the system share sheet.
5. Open History (「记录」) to inspect saved tasks, steps, tool results, and final outputs; swipe a task to delete it. Under Me → Memory management (「我的 → 记忆管理」), manually save or delete memory. A completed workflow is not a guarantee of factual accuracy.
6. Under Me, 「隐私政策」 opens the bundled policy. To withdraw sharing, select that provider in API configuration, turn off its sharing switch, and save. New AI requests to it are blocked.
7. 「清除全部数据」 clears app-managed local keys, memory, run records, checkpoints, and the Application Support workspace after confirmation. It does not delete provider-held data or revoke keys at the provider.

The configured providers are Anthropic, OpenAI, DeepSeek, and xAI. Requests are sent directly over HTTPS to the selected provider. They include the prompt, up to six recent conversation messages within text limits, relevant manually saved memory, task context and, when needed, previous step/tool results. The provider's key is sent for authentication. Sharing consent is stored separately for each provider. The app contains no advertising or third-party analytics SDK.

Workspace (「工作台」) provides task starters and access to saved memory. iOS tools remain subject to the app sandbox. The app does not provide a full Linux terminal, background device control, image generation, or video generation.

## 仅在私密审核信息补齐

- 测试服务商与模型：**待确认**（需使用发布包验证，不能只根据模型名称列表判断可用）。
- 专用测试 API Key 与有效额度：**待填写**。
- 审核联系人姓名、电话、邮箱：**待填写**。
- 发布主体、版权、第三方服务使用权及隐私申报：**待确认**。
- 后台问卷和提交状态：**待核对 App Store Connect**。

审核期间维持测试访问可用，处理结束后按凭据使用情况管理或吊销。不要将真实 Key 写入本文件、商店公开描述、截图、GitHub Issue 或提交记录。
