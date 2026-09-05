import Foundation

struct NexusExternalModels {
    static let openGPT = NexusModelEntry(providerID: "opengpt", providerType: .openAICompatible, providerURL: "https://api.openai.com/v1", modelID: "gpt-5", displayName: "GPT-5", isHidden: false)
    static let deepSeek = NexusModelEntry(providerID: "deepseek", providerType: .openAICompatible, providerURL: "https://api.deepseek.com/v1", modelID: "deepseek-reasoner", displayName: "DeepSeek Reasoner", isHidden: false)
    static let grok = NexusModelEntry(providerID: "xai", providerType: .openAICompatible, providerURL: "https://api.x.ai/v1", modelID: "grok-4", displayName: "Grok 4", isHidden: false)

    static let all = [openGPT, deepSeek, grok]
}
