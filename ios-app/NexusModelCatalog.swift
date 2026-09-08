import Foundation

struct NexusModelCatalog {
    static let entries: [NexusModelEntry] = [
        NexusModelEntry(providerID: "anthropic", providerType: .anthropic, providerURL: "https://api.anthropic.com", modelID: "claude-opus-5", displayName: "Claude Opus 5", isHidden: false),
        NexusModelEntry(providerID: "anthropic", providerType: .anthropic, providerURL: "https://api.anthropic.com", modelID: "claude-fable-5", displayName: "Claude Fable 5", isHidden: false),
        NexusModelEntry(providerID: "opengpt", providerType: .openAICompatible, providerURL: "https://api.openai.com/v1", modelID: "gpt-5", displayName: "GPT-5", isHidden: false),
        NexusModelEntry(providerID: "deepseek", providerType: .openAICompatible, providerURL: "https://api.deepseek.com/v1", modelID: "deepseek-reasoner", displayName: "DeepSeek Reasoner", isHidden: false),
        NexusModelEntry(providerID: "xai", providerType: .openAICompatible, providerURL: "https://api.x.ai/v1", modelID: "grok-4", displayName: "Grok 4", isHidden: false),
        NexusModelEntry(providerID: "apiclaude", providerType: .openAICompatible, providerURL: "https://apiclaude.cc/v1", modelID: "gpt-6-astra", displayName: "GPT-6 Astra", isHidden: false)
    ]
    static func entry(for modelID: String) -> NexusModelEntry {
        if let saved = NexusKeychain.shared.selectedConnection, saved.modelID == modelID { return saved }
        if let entry = entries.first(where: { $0.modelID == modelID }) { return entry }
        if modelID.hasPrefix("claude-") {
            return NexusModelEntry(providerID: "anthropic", providerType: .anthropic, providerURL: "https://api.anthropic.com", modelID: modelID, displayName: modelID, isHidden: false)
        }
        return NexusModelEntry(providerID: "unconfigured", providerType: .openAICompatible, providerURL: "", modelID: modelID, displayName: modelID, isHidden: false)
    }
}
