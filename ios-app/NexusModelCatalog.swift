import Foundation

/// 一个可直连的模型服务商。
struct NexusProviderInfo {
    let id: String
    let type: NexusProviderType
    let url: String
    let displayName: String
    let keyHint: String
}

/// 全 App 唯一的模型/服务商目录来源。其它地方（客户端、注册表、配置页）都从这里取，
/// 避免多份列表漂移导致「选了 A 模型却按 B 服务商路由」。
struct NexusModelCatalog {
    static let providers: [NexusProviderInfo] = [
        NexusProviderInfo(id: "anthropic", type: .anthropic, url: "https://api.anthropic.com", displayName: "Anthropic", keyHint: "console.anthropic.com"),
        NexusProviderInfo(id: "openai", type: .openAICompatible, url: "https://api.openai.com/v1", displayName: "OpenAI", keyHint: "platform.openai.com"),
        NexusProviderInfo(id: "deepseek", type: .openAICompatible, url: "https://api.deepseek.com/v1", displayName: "DeepSeek", keyHint: "platform.deepseek.com"),
        NexusProviderInfo(id: "xai", type: .openAICompatible, url: "https://api.x.ai/v1", displayName: "xAI · Grok", keyHint: "console.x.ai")
    ]

    static let entries: [NexusModelEntry] = [
        make("anthropic", "claude-opus-5", "Claude Opus 5"),
        make("anthropic", "claude-fable-5-1", "Claude Fable 5.1"),
        make("anthropic", "claude-sonnet-4-6", "Claude Sonnet 4.6"),
        make("anthropic", "claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
        make("openai", "gpt-5", "GPT-5"),
        make("deepseek", "deepseek-reasoner", "DeepSeek Reasoner"),
        make("xai", "grok-4", "Grok 4")
    ]

    static var defaultModelID: String { entries[0].modelID }

    static func provider(for id: String) -> NexusProviderInfo {
        providers.first(where: { $0.id == id }) ?? providers[0]
    }

    static func entry(for modelID: String) -> NexusModelEntry {
        entries.first(where: { $0.modelID == modelID }) ?? entries[0]
    }

    private static func make(_ providerID: String, _ modelID: String, _ displayName: String) -> NexusModelEntry {
        let p = providers.first(where: { $0.id == providerID }) ?? providers[0]
        return NexusModelEntry(providerID: p.id, providerType: p.type, providerURL: p.url,
                               modelID: modelID, displayName: displayName, isHidden: false)
    }
}
