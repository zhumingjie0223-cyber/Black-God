import Foundation

struct NexusModelCatalog {
    static let entries: [NexusModelEntry] = [
        NexusModelEntry(providerID: "anthropic", providerType: .anthropic, providerURL: "https://api.anthropic.com", modelID: "claude-opus-5", displayName: "Claude Opus 5", isHidden: false),
        NexusModelEntry(providerID: "anthropic", providerType: .anthropic, providerURL: "https://api.anthropic.com", modelID: "claude-fable-5", displayName: "Claude Fable 5", isHidden: false),
        NexusModelEntry(providerID: "opengpt", providerType: .openAICompatible, providerURL: "https://api.openai.com/v1", modelID: "gpt-5", displayName: "GPT-5", isHidden: false),
        NexusModelEntry(providerID: "deepseek", providerType: .openAICompatible, providerURL: "https://api.deepseek.com/v1", modelID: "deepseek-reasoner", displayName: "DeepSeek Reasoner", isHidden: false),
        NexusModelEntry(providerID: "xai", providerType: .openAICompatible, providerURL: "https://api.x.ai/v1", modelID: "grok-4", displayName: "Grok 4", isHidden: false)
    ]
    static func entry(for modelID: String) -> NexusModelEntry {
        entries.first(where: { $0.modelID == modelID }) ?? entries[0]
    }
}
