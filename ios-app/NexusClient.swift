// NexusClient.swift — 用户许可后的直连请求；严格、可取消且有时间上限的 SSE 传输

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
    let blocks: [NexusAssistantToolUseBlock]?

    init(role: String, content: String, blocks: [NexusAssistantToolUseBlock]? = nil) {
        self.role = role
        self.content = content
        self.blocks = blocks
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

    private let defaultModel = NexusModelCatalog.defaultModelID
    private let configuration: URLSessionConfiguration
    private let timeout: TimeInterval
    private let maxResponseCharacters: Int

    init(configuration: URLSessionConfiguration = .ephemeral, timeout: TimeInterval = 120,
         maxResponseCharacters: Int = 64_000) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.timeout = min(max(timeout, 0.01), 120)
        self.maxResponseCharacters = min(max(maxResponseCharacters, 1), 64_000)
    }

    // MARK: 流式对话

    func streamChat(
        messages: [ChatMessage],
        model: String? = nil,
        onDelta: @escaping (String) -> Void,
        onToolCall: @escaping (NexusToolCall) -> Void = { _ in },
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        // Native tool schemas are not requested: the executor owns the text tool protocol.
        // Retain this callback argument for bridge compatibility, but never execute unexpected calls.
        _ = onToolCall
        do {
            try Task.checkCancellation()
            let entry = NexusModelCatalog.entry(for: model ?? defaultModel)
            guard NexusKeychain.shared.hasSharingConsent(for: entry.providerID) else {
                throw NexusError.apiError("请先在 API 配置中确认向所选 AI 服务商发送数据。")
            }
            guard let apiKey = NexusKeychain.shared.key(for: entry.providerID), !apiKey.isEmpty else {
                throw NexusError.missingAPIKey
            }
            guard let url = NexusProviderRequestBuilder.adapter(for: entry).endpoint(for: entry),
                  url.scheme?.lowercased() == "https", url.host != nil else {
                throw NexusError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpBody = try NexusProviderRequestBuilder.body(model: entry, messages: messages)
            for (name, value) in NexusProviderRequestBuilder.adapter(for: entry).headers(for: entry, apiKey: apiKey) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            let config = configuration.copy() as! URLSessionConfiguration
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout
            config.urlCache = nil
            config.httpCookieStorage = nil
            let delegate = NexusProviderSessionDelegate(origin: url)
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
            let watchdog = Task {
                do { try await Task.sleep(for: .seconds(timeout)) }
                catch { return }
                session.invalidateAndCancel()
            }
            defer { watchdog.cancel() }
            do {
                try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let response = response as? HTTPURLResponse else { throw NexusError.invalidResponse }
                    guard response.statusCode == 200 else { throw NexusError.apiError("HTTP \(response.statusCode)") }
                    guard response.mimeType?.lowercased() == "text/event-stream" else { throw NexusError.invalidResponse }
                    var parser = NexusSSEParser(format: entry.providerType == .anthropic ? .anthropic : .openAICompatible,
                                                maxResponseCharacters: maxResponseCharacters)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard ContinuousClock.now < deadline else { throw NexusStreamError.timedOut }
                        if let delta = try parser.consume(byte) { onDelta(delta) }
                        if parser.completed { break }
                    }
                    try Task.checkCancellation()
                    try parser.finish()
                } onCancel: {
                    session.invalidateAndCancel()
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if ContinuousClock.now >= deadline || (error as? URLError)?.code == .timedOut {
                    throw NexusStreamError.timedOut
                }
                throw error
            }
            // A single terminal callback, after the provider's normal finish marker.
            try Task.checkCancellation()
            onComplete()
        } catch {
            onError(error)
        }
    }

    func toolResultMessage(_ result: NexusToolResult) -> NexusToolResultMessage {
        NexusToolResultMessage(content: [NexusToolResultBlock(toolUseID: result.callID.uuidString, content: result.output, isError: !result.succeeded)])
    }

    // MARK: 可用模型列表

    func availableModels() -> [String] {
        NexusModelCatalog.entries.map { $0.modelID }
    }
}

/// Never forward a provider credential to another origin through an HTTP redirect.
final class NexusProviderSessionDelegate: NSObject, URLSessionTaskDelegate {
    private let origin: URL
    init(origin: URL) { self.origin = origin }

    func allows(_ destination: URL?) -> Bool {
        guard let destination else { return false }
        return destination.scheme?.lowercased() == "https"
            && destination.host?.lowercased() == origin.host?.lowercased()
            && (destination.port ?? 443) == (origin.port ?? 443)
            && destination.user == nil && destination.password == nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(allows(request.url) ? request : nil)
    }
}
