# Black God 隐私与数据使用 / Privacy and data use

更新日期 / Updated: 2026-09-09

## 中文

Black God 是独立的多服务商 AI 客户端，支持本机工具和内置 Linux 运行环境。开发者没有部署接收聊天内容的中转服务器，也没有集成广告、分析或自动崩溃上报服务；这不表示应用没有网络传输。

### 本机保存

API 密钥、OAuth 访问令牌和刷新令牌存放在本机 Keychain，设置为仅此设备可用。连接配置、对话、记忆、技能、任务检查点和运行文件保存在应用容器。容器数据是否包含在系统备份中取决于系统设置；Keychain 凭据可能在卸载后保留，不承诺卸载会删除所有凭据。

### 数据发送与许可

在你明确允许某个连接发送内容后，模型请求会把当前对话、选用的长期记忆、技能指令和工具结果发送至你配置的服务商。这些内容可能包含个人信息和文件内容。服务商收到认证凭据、请求与网络连接信息，可将使用情况关联至其账号。数据保留与处理由相应服务商及其下游服务政策决定。

“我的 → 神枢连接”显示接收地址及发送内容，并提供许可开关。关闭许可阻止后续模型内容请求；已发送的请求或服务商已保留的数据不会因此撤回。获取模型列表会向该服务商发送认证凭据，不会发送对话内容。

账号授权时，登录页面、验证码、授权码、PKCE 材料和令牌交换由相应授权服务处理。应用不索取服务商密码。OpenRouter 是聚合服务，可能将模型请求交由其下游提供商处理。Kimi、Grok 和 MiniMax 的兼容登录使用公开 CLI 授权流程，权限与额度由服务商决定。

### 工具与运行环境

启用并运行联网工具、脚本或软件包命令后，请求可能访问命令指定的网站和软件仓库。工具输出可用于后续模型回合。请在执行前查看任务计划，避免让工具读取或发送不必要的敏感信息。设备实际剩余存储空间只用于本机空间显示和写入保护。

### 神枢成长与图片观察

用户选取的图片通过 Apple Vision 在本机识别文字，当前不把原图发送至模型。图片的 SHA-256 校验值、识别时间和可编辑的识别文本用于资料候选；识别可能出错。候选须由用户核对后启用；启用的资料、来源和校验值可能随之后获准的模型请求发送。模型工具权限与连接的数据发送许可分开管理。治理记录在本机保存资料版本和权限/工具审计；审计保存参数哈希，不保存原始参数，但哈希不等于匿名化。撤回资料会停止后续使用，历史记录仍保留以支持复核。

### 管理与删除

可以在对话、记忆和技能页面删除对应记录，在运行环境页面清理工作空间。OAuth 连接可通过“断开此连接”清除本机授权凭据；服务商侧的撤销与数据删除需在其账号页面办理。手填密钥可在连接设置中清空后保存。应用没有 Black God 自有账号，也不提供一个会同时清除所有数据的一键按钮。

### 联系与政策变化

支持与隐私请求：https://github.com/zhumingjie0223-cyber/Black-God/issues 。请勿在公开问题中粘贴密钥、密码或私人对话。政策更新会修改本文日期。应用不面向儿童设计；商店年龄分级以实际内容问卷和审核结果为准。

## English

Black God is an independent AI client with local tools and an embedded Linux environment. The developer operates no chat relay and integrates no advertising, analytics or automatic crash-reporting service. The app nevertheless transmits data to the services you use.

API keys and OAuth access/refresh tokens are stored in this-device-only Keychain entries. Connections, chats, memories, skills, task checkpoints and workspace files are stored in the app container. System backups depend on device settings. Keychain entries may survive uninstalling the app.

After you explicitly allow a connection, model requests send the current conversation, selected memories, skill instructions and tool results to its configured provider. These may contain personal information or file content. Authentication and network information can associate requests with your provider account. Provider and downstream policies govern retention and processing. OpenRouter may route requests to downstream model providers.

The connection screen displays the destination, explains the data and provides a permission switch. Turning permission off prevents subsequent model-content requests; it cannot recall data already sent. Model discovery sends authentication credentials but no conversation. Account login and code/token exchange use provider authorization services; Black God does not ask for provider passwords. Kimi, Grok and MiniMax compatibility sign-in uses public CLI authorization flows.

Network-enabled tools, scripts and package commands may contact their specified websites or repositories. Tool output may enter later model requests. Review task plans and avoid unnecessary sensitive data. Actual device free space is used locally for display and write protection.

Delete individual chats, memories and skills in their respective screens and clear workspace files in the runtime screen. Disconnect an OAuth connection to remove its local credential; provider-side revocation and deletion are managed with that provider. Clear and save a manually entered key to remove it. There is no Black God account and no single button that deletes every data category.

Support and privacy requests: https://github.com/zhumingjie0223-cyber/Black-God/issues . Do not post credentials or private conversations publicly. Policy changes update this date. The app is not designed for children; its store rating depends on the actual questionnaire and review.

Images selected by the user are processed locally with Apple Vision OCR; the current feature does not send the original image to a model. Editable extracted text, an image SHA-256 digest and recognition time form a candidate record. Only after user review and activation can that record and source information enter subsequent permitted model requests. Tool permissions are separate from connection data consent. Local governance records retain knowledge revisions and tool/permission audit events. Audits store argument hashes, not raw arguments; hashes are not anonymization. Withdrawing a record prevents future use but retains its history for review.


自我状态流在本机保存最近120条目标摘要、执行阶段、工具返回状态和模型公开自评；这不是内部思维链。较早记录滚动移除并显示计数，当前连接凭据按精确匹配隐藏，但不保证识别其他秘密。最近6条摘要可能随后续获准的模型请求发送。用户可在“神枢成长 → 自我状态流”暂停或清空；这不会删除聊天、知识、任务检查点、系统备份或服务商已有的数据。状态流按任务事件更新，不额外调用模型，应用休眠时不持续运行。

The self-state stream stores the latest 120 goal summaries, task phases, tool return statuses and public model assessments locally, not private chain-of-thought. Older entries roll off with an omission count. The current connection credential is redacted by exact match, which does not identify every possible secret. The latest six summaries may enter subsequent permitted model requests. Users can pause or clear the stream under Cognitive Growth → Self-State Stream; this does not delete chats, knowledge, task checkpoints, system backups or provider-held data. Updates follow task events without extra model requests or continuous execution while the app is suspended.
