import Foundation

struct OpenAIRequest: Codable {
    let model: String
    let stream: Bool
    let messages: [AnthropicMessage]
}

struct NexusProviderRequestBuilder {
    static func body(model: NexusModelEntry, messages: [ChatMessage]) throws -> Data {
        switch model.providerType {
        case .anthropic:
            return try JSONEncoder().encode(AnthropicRequest(model: model.modelID, maxTokens: 4096, stream: true, messages: messages.map { AnthropicMessage(role: $0.role, content: $0.content) }))
        case .openAICompatible:
            return try JSONEncoder().encode(OpenAIRequest(model: model.modelID, stream: true, messages: messages.map { AnthropicMessage(role: $0.role, content: $0.content) }))
        }
    }

    static func adapter(for model: NexusModelEntry) -> any NexusProviderAdapter {
        model.providerType == .anthropic ? AnthropicProviderAdapter() : OpenAICompatibleProviderAdapter()
    }
}
