import Foundation

struct OpenAIRequest: Codable {
    let model: String
    let stream: Bool
    let messages: [AnthropicMessage]
    let tools: [NexusToolDefinition]?
}

// 当前执行器通过文本协议调用已注册工具，不向服务商声明尚未接通的原生工具。
struct NexusProviderRequestBuilder {
    static func body(model: NexusModelEntry, messages: [ChatMessage]) throws -> Data {
        switch model.providerType {
        case .anthropic:
            return try JSONEncoder().encode(AnthropicRequest(model: model.modelID, maxTokens: 4096, stream: true, messages: messages.map { AnthropicMessage(role: $0.role, content: $0.content) }, tools: nil))
        case .gemini, .responses:
            return try NexusAdditionalProtocols.body(model: model, messages: messages.map { .text(role: $0.role, content: $0.content) }, tools: [])
        case .openAICompatible:
            return try JSONEncoder().encode(OpenAIRequest(model: model.modelID, stream: true, messages: messages.map { AnthropicMessage(role: $0.role, content: $0.content) }, tools: nil))
        }
    }

    static func request(model: NexusModelEntry, messages: [ChatMessage], apiKey: String) throws -> URLRequest {
        guard !model.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !messages.isEmpty, messages.allSatisfy({ ["user", "assistant"].contains($0.role) }),
              let endpoint = adapter(for: model).endpoint(for: model) else {
            throw NexusError.apiError("请填写有效的 HTTPS 接口地址、模型名称和对话内容。")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.httpBody = try body(model: model, messages: messages)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in adapter(for: model).headers(for: model, apiKey: apiKey) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    static func adapter(for model: NexusModelEntry) -> any NexusProviderAdapter {
        switch model.providerType {
        case .anthropic: return AnthropicProviderAdapter()
        case .openAICompatible: return OpenAICompatibleProviderAdapter()
        case .gemini, .responses: return GenericProviderAdapter(type: model.providerType)
        }
    }
}
