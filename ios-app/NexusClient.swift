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

/// 禁止自动跟随重定向，避免把密钥发往配置之外的地址。
private final class NexusRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor NexusClient {
    static let shared = NexusClient()
    private let session: URLSession
    private let keyProvider: (String) -> String?
    private let resolver: (String) -> NexusModelEntry
    private let consentValidator: (NexusModelEntry) throws -> Void
    private let credentialResolver: (NexusModelEntry, String) async throws -> String
    init(session: URLSession? = nil,
         keyProvider: @escaping (String) -> String? = { NexusKeychain.shared.key(for: $0) },
         resolver: @escaping (String) -> NexusModelEntry = { NexusModelCatalog.entry(for: $0) },
         credentialResolver: @escaping (NexusModelEntry, String) async throws -> String = { try await NexusOAuthCredentials.shared.resolve($0, fallback: $1) },
         consentValidator: @escaping (NexusModelEntry) throws -> Void = { try NexusDataConsent.shared.require($0) }) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 180
            self.session = URLSession(configuration: configuration)
        }
        self.keyProvider = keyProvider
        self.resolver = resolver
        self.credentialResolver = credentialResolver
        self.consentValidator = consentValidator
    }

    func complete(messages: [ChatMessage], model: String? = nil) async throws -> String {
        let entry = resolver(model ?? NexusKeychain.shared.selectedModel)
        guard let key = keyProvider(entry.credentialID), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NexusError.missingAPIKey
        }
        return try await complete(messages: messages, entry: entry, apiKey: key)
    }

    /// 连接测试使用未保存的配置，不会覆盖用户正在使用的连接。
    func complete(messages: [ChatMessage], entry: NexusModelEntry, apiKey: String,
                  onDelta: @escaping (String) -> Void = { _ in }) async throws -> String {
        try consentValidator(entry)
        try Task.checkCancellation()
        let key = try await credentialResolver(entry, apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        guard !key.isEmpty else { throw NexusError.missingAPIKey }
        if entry.providerType == .gemini || entry.providerType == .responses {
            let reply = try await nativeTurn(messages: messages.map { .text(role: $0.role, content: $0.content) }, tools: [], entry: entry, apiKey: key)
            guard reply.calls.isEmpty else { throw NexusError.invalidResponse }
            onDelta(reply.text)
            return reply.text
        }
        let request = try NexusProviderRequestBuilder.request(model: entry, messages: messages, apiKey: key)
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request, delegate: NexusRedirectGuard())
            guard let http = response as? HTTPURLResponse else { throw NexusError.invalidResponse }
            guard http.statusCode == 200 else {
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                    if data.count >= 16384 { break }
                }
                throw NexusError.apiError(Self.httpError(status: http.statusCode, data: data, redacting: key))
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if contentType.contains("application/json") {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard data.count < 2_000_000 else { throw NexusError.apiError("回答超过本机接收上限。") }
                    data.append(byte)
                }
                var content = NexusStreamContent(providerType: entry.providerType)
                let text = try content.receiveJSON(data)
                onDelta(text)
                return text
            }
            guard contentType.contains("text/event-stream") else {
                throw NexusError.apiError("接口没有返回流式响应，请检查地址、协议和模型。")
            }
            var decoder = NexusSSEDecoder()
            var content = NexusStreamContent(providerType: entry.providerType)
            for try await byte in bytes {
                try Task.checkCancellation()
                if let event = try decoder.append(byte) {
                    if let delta = try content.receive(event) { onDelta(delta) }
                    if content.completed { break }
                }
            }
            if !content.completed, let event = try decoder.finish() {
                if let delta = try content.receive(event) { onDelta(delta) }
            }
            try Task.checkCancellation()
            try content.validateEnd()
            return content.output
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            // 部分兼容服务会在报错中回显输入，诊断中不暴露密钥。
            let message = error.localizedDescription.replacingOccurrences(of: key, with: "[密钥已隐藏]")
            throw NexusError.apiError(message)
        }
    }

    func nativeTurn(messages: [NexusNativeMessage], tools: [NexusToolDefinition], model: String? = nil) async throws -> NexusNativeReply {
        let entry = resolver(model ?? NexusKeychain.shared.selectedModel)
        guard let storedKey = keyProvider(entry.credentialID) else { throw NexusError.missingAPIKey }
        return try await nativeTurn(messages: messages, tools: tools, entry: entry, apiKey: storedKey)
    }

    func nativeTurn(messages: [NexusNativeMessage], tools: [NexusToolDefinition], entry: NexusModelEntry, apiKey: String) async throws -> NexusNativeReply {
        try consentValidator(entry)
        try Task.checkCancellation()
        let key = try await credentialResolver(entry, apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        guard !key.isEmpty else { throw NexusError.missingAPIKey }
        var request = try NexusProviderRequestBuilder.request(model: entry, messages: [ChatMessage(role: "user", content: "工具回合")], apiKey: key)
        request.httpBody = try NexusNativeCodec.body(model: entry, messages: messages, tools: tools)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request, delegate: NexusRedirectGuard())
            guard let http = response as? HTTPURLResponse else { throw NexusError.invalidResponse }
            var data = Data()
            let limit = http.statusCode == 200 ? 2_000_000 : 16384
            for try await byte in bytes {
                try Task.checkCancellation()
                if data.count >= limit {
                    if http.statusCode != 200 { break }
                    throw NexusError.apiError("模型工具响应超过接收上限。")
                }
                data.append(byte)
            }
            guard http.statusCode == 200 else {
                throw NexusError.apiError(Self.httpError(status: http.statusCode, data: data, redacting: key))
            }
            guard (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().contains("application/json") else {
                throw NexusError.apiError("工具接口必须返回完整 JSON，请检查服务商的工具调用支持。")
            }
            try Task.checkCancellation()
            return try NexusNativeCodec.decode(data, type: entry.providerType)
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw NexusError.apiError(error.localizedDescription.replacingOccurrences(of: key, with: "[密钥已隐藏]"))
        }
    }

    func fetchModels(entry: NexusModelEntry, apiKey: String) async throws -> [NexusRemoteModel] {
        try Task.checkCancellation()
        let key = try await credentialResolver(entry, apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        guard !key.isEmpty else { throw NexusError.missingAPIKey }
        guard entry.validWorkspace, let url = NexusModelsAPI.endpoint(entry) else { throw NexusError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in NexusProviderRequestBuilder.adapter(for: entry).headers(for: entry, apiKey: key) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request, delegate: NexusRedirectGuard())
            guard let http = response as? HTTPURLResponse else { throw NexusError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 2_000_000 else { throw NexusError.apiError("模型列表超过接收上限。") }
                data.append(byte)
                if http.statusCode != 200 && data.count >= 16384 { break }
            }
            guard http.statusCode == 200 else { throw NexusError.apiError(Self.httpError(status: http.statusCode, data: data, redacting: key)) }
            let models = try NexusModelsAPI.decode(data, type: entry.providerType)
            guard !models.isEmpty else { throw NexusError.apiError("接口未返回可用模型，请根据服务商控制台手动填写。") }
            return models
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw NexusError.apiError(error.localizedDescription.replacingOccurrences(of: key, with: "[密钥已隐藏]"))
        }
    }

    func streamChat(messages: [ChatMessage], model: String? = nil,
                    onDelta: @escaping (String) -> Void,
                    onToolCall: @escaping (NexusToolCall) -> Void = { _ in },
                    onComplete: @escaping () -> Void, onError: @escaping (Error) -> Void) async {
        do {
            let entry = resolver(model ?? NexusKeychain.shared.selectedModel)
            guard let key = keyProvider(entry.credentialID) else { throw NexusError.missingAPIKey }
            _ = try await complete(messages: messages, entry: entry, apiKey: key, onDelta: onDelta)
            onComplete()
        } catch { onError(error) }
    }

    static func httpError(status: Int, data: Data, redacting key: String = "") -> String {
        let hint: String
        switch status {
        case 401: hint = "密钥无效或已过期"
        case 403: hint = "当前密钥没有访问权限"
        case 404: hint = "接口地址或模型不存在"
        case 429: hint = "请求过于频繁或额度不足"
        case 300..<400: hint = "接口发生重定向，请直接填写最终 HTTPS 地址"
        case 500...599: hint = "服务商暂时不可用"
        default: hint = "服务商拒绝了请求"
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        var detail = (object?["error"] as? [String: Any])?["message"] as? String
        if !key.isEmpty { detail = detail?.replacingOccurrences(of: key, with: "[密钥已隐藏]") }
        return "\(hint)（HTTP \(status)）" + (detail.map { "：" + String($0.prefix(500)) } ?? "")
    }

    func toolResultMessage(_ result: NexusToolResult) -> NexusToolResultMessage {
        NexusToolResultMessage(content: [NexusToolResultBlock(toolUseID: result.callID.uuidString, content: result.output, isError: !result.succeeded)])
    }
    func availableModels() -> [String] { NexusModelCatalog.entries.map(\.modelID) }
}
