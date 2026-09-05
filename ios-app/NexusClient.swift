// NexusClient.swift — 纯客户端直连 Anthropic API
// 用户自带 API key，存 Keychain，直连，零后端依赖

import Foundation

// MARK: - 数据模型

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var role: String   // "user" | "assistant"
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = Date()
    }
}

struct AnthropicMessage: Codable {
    let role: String
    let content: String

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

struct AnthropicRequest: Codable {
    let model: String
    let maxTokens: Int
    let stream: Bool
    let messages: [AnthropicMessage]
    let tools: [NexusToolDefinition]?

    enum CodingKeys: String, CodingKey {
        case model, stream, messages, tools
        case maxTokens = "max_tokens"
    }
}

// MARK: - 错误

enum NexusError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return L10n.tr("error.missing_api_key")
        case .invalidResponse: return L10n.tr("error.invalid_response")
        case .apiError(let msg): return msg
        case .networkError(let e): return L10n.tr("error.network", e.localizedDescription)
        }
    }
}

// MARK: - 客户端

actor NexusClient {
    static let shared = NexusClient()

    private let defaultModel = "claude-opus-5"
    private let nativeModel = NexusModelEntry(providerID: "anthropic", providerType: .anthropic, providerURL: "https://api.anthropic.com", modelID: "claude-opus-5", displayName: "Claude Opus 5", isHidden: false)

    // MARK: 流式对话

    func streamChat(
        messages: [ChatMessage],
        model: String? = nil,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        let selectedModel = model ?? defaultModel
        let entry = NexusModelCatalog.entry(for: selectedModel)
        guard let apiKey = NexusKeychain.shared.key(for: entry.providerID), !apiKey.isEmpty else {
            onError(NexusError.missingAPIKey)
            return
        }
        guard let url = NexusProviderRequestBuilder.adapter(for: entry).endpoint(for: entry),
              let bodyData = try? NexusProviderRequestBuilder.body(model: entry, messages: messages) else {
            onError(NexusError.invalidResponse)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        for (name, value) in NexusProviderRequestBuilder.adapter(for: entry).headers(for: entry, apiKey: apiKey) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                onError(NexusError.invalidResponse)
                return
            }

            guard httpResponse.statusCode == 200 else {
                onError(NexusError.apiError("HTTP \(httpResponse.statusCode)"))
                return
            }

            // SSE 解析
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let data = String(line.dropFirst(6))
                guard data != "[DONE]" else { break }

                if let json = data.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any] {
                    if entry.providerType == .openAICompatible,
                       let choices = obj["choices"] as? [[String: Any]],
                       let delta = choices.first?["delta"] as? [String: Any],
                       let text = delta["content"] as? String {
                        onDelta(text)
                    } else if let type_ = obj["type"] as? String,
                              type_ == "content_block_delta",
                              let delta = obj["delta"] as? [String: Any],
                              let text = delta["text"] as? String {
                        onDelta(text)
                    } else if obj["type"] as? String == "message_stop" {
                        break
                    }
                }
            }
            onComplete()

        } catch {
            onError(NexusError.networkError(error))
        }
    }

    func toolResultMessage(_ result: NexusToolResult) -> ChatMessage {
        ChatMessage(role: "user", content: "[tool_result:\(result.callID)]\n\(result.output)")
    }

    // MARK: 可用模型列表

    func availableModels() -> [String] {
        [
            "claude-opus-5",
            "claude-fable-5-1",
            "claude-opus-4-8",
            "claude-sonnet-4-6",
            "claude-haiku-4-5-20251001",
        ]
    }
}
