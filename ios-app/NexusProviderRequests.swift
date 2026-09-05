import Foundation

struct OpenAIRequest: Codable {
    let model: String
    let stream: Bool
    let messages: [AnthropicMessage]
    let tools: [NexusToolDefinition]?
}

struct NexusProviderRequestBuilder {
    // 工具闭环由 Executor 用文本 ```tool 约定驱动（跨服务商统一），因此请求体不下发原生工具 schema，
    // 避免模型走原生 tool_use（当前流式桥不回灌原生工具结果）导致闭环断裂。
    static func body(model: NexusModelEntry, messages: [ChatMessage]) throws -> Data {
        switch model.providerType {
        case .anthropic:
            return try JSONEncoder().encode(AnthropicRequest(model: model.modelID, maxTokens: 4096, stream: true, messages: messages.map { AnthropicMessage(role: $0.role, content: $0.content) }, tools: nil))
        case .openAICompatible:
            return try JSONEncoder().encode(OpenAIRequest(model: model.modelID, stream: true, messages: messages.map { AnthropicMessage(role: $0.role, content: $0.content) }, tools: nil))
        }
    }

    static func adapter(for model: NexusModelEntry) -> any NexusProviderAdapter {
        model.providerType == .anthropic ? AnthropicProviderAdapter() : OpenAICompatibleProviderAdapter()
    }
}
