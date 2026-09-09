import Foundation

struct NexusProviderPreset: Identifiable {
    let id: String
    let name: String
    let type: NexusProviderType
    let baseURL: String
    let note: String
    let documentation: String
    var entry: NexusModelEntry {
        NexusModelEntry(providerID: id, providerType: type, providerURL: baseURL,
            modelID: "", displayName: name, isHidden: false)
    }
}

/// Model names are fetched from the account or entered by the user, never invented.
enum NexusProviderPresets {
    static let all: [NexusProviderPreset] = [
        .init(id: "openrouter", name: "OpenRouter", type: .openAICompatible, baseURL: "https://openrouter.ai/api/v1", note: "支持 OAuth 账号登录，授权后自动返回并保存凭据；使用 OpenRouter 账号的额度。", documentation: "https://openrouter.ai/docs/guides/overview/auth/oauth"),
        .init(id: "opengpt", name: "OpenAI", type: .responses, baseURL: "https://api.openai.com/v1", note: "支持 Responses 和 Chat Completions；请选择账号有权限使用的模型。", documentation: "https://developers.openai.com/api/docs/guides/function-calling"),
        .init(id: "anthropic", name: "Anthropic / Claude", type: .anthropic, baseURL: "https://api.anthropic.com", note: "使用 Anthropic API 密钥；支持 Messages 与工具结果回传。", documentation: "https://docs.anthropic.com/en/api/messages"),
        .init(id: "gemini", name: "Google Gemini", type: .gemini, baseURL: "https://generativelanguage.googleapis.com/v1beta", note: "使用 Google AI Studio 的 Gemini API 密钥，接入原生 generateContent。", documentation: "https://ai.google.dev/api/generate-content"),
        .init(id: "dashscope", name: "阿里云百炼 / 通义千问", type: .openAICompatible, baseURL: "", note: "请从百炼控制台复制与你的业务空间、地域一致的完整 OpenAI 兼容 BASE_URL。各地域地址与密钥不能混用。", documentation: "https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope"),
        .init(id: "volcengine", name: "火山方舟 / 豆包", type: .openAICompatible, baseURL: "https://ark.cn-beijing.volces.com/api/v3", note: "填写控制台已开通的模型 ID 或推理接入点 ID；模型列表接口可能不可用，可手动输入。", documentation: "https://www.volcengine.com/docs/82379/1494384"),
        .init(id: "deepseek", name: "DeepSeek", type: .openAICompatible, baseURL: "https://api.deepseek.com/v1", note: "使用 DeepSeek 开放平台 API 密钥。推理模型的必要回传字段会保留。", documentation: "https://api-docs.deepseek.com/"),
        .init(id: "zhipu", name: "智谱 / GLM", type: .openAICompatible, baseURL: "https://open.bigmodel.cn/api/paas/v4", note: "此为标准按量 API 地址；Coding Plan 等产品请按账号文档修改地址。", documentation: "https://docs.bigmodel.cn/cn/guide/start/model-overview"),
        .init(id: "moonshot", name: "Moonshot / Kimi", type: .openAICompatible, baseURL: "https://api.moonshot.cn/v1", note: "使用 Kimi 开放平台 API 密钥；中国区与其他地域配置需对应。", documentation: "https://platform.kimi.com/docs/get-api-key"),
        .init(id: "minimax", name: "MiniMax", type: .openAICompatible, baseURL: "https://api.minimaxi.com/v1", note: "使用 MiniMax 中国区 API 密钥；其他地域请替换为账号对应的地址。", documentation: "https://platform.minimaxi.com/docs/api-reference/text-openai-api"),
        .init(id: "hunyuan", name: "腾讯混元", type: .openAICompatible, baseURL: "https://api.hunyuan.cloud.tencent.com/v1", note: "使用混元 OpenAI 兼容接口的 API Key，不是腾讯云 SecretId/SecretKey。", documentation: "https://cloud.tencent.cn/document/product/1729/111007"),
        .init(id: "xai", name: "xAI / Grok", type: .openAICompatible, baseURL: "https://api.x.ai/v1", note: "使用 xAI API 密钥；根据账号权限获取或填写模型。", documentation: "https://docs.x.ai/docs/api-reference")
    ] + NexusDeviceProvider.allCases.map { provider in
        NexusProviderPreset(id: provider.rawValue, name: provider.name + " · OAuth", type: provider.type,
            baseURL: provider.baseURL, note: "兼容账号登录；授权页面可能显示 " + provider.authorizationName + "。额度和调用权限以服务商为准，尚未完成真实账号验收。", documentation: provider.documentation)
    }
}
