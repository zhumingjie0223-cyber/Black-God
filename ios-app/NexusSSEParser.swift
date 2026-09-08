import Foundation

/// Streaming response failures never turn a partial answer into a successful result.
enum NexusStreamError: LocalizedError, Equatable {
    case malformedEvent, unexpectedEnd, emptyResponse, responseTooLarge, timedOut
    case providerError(String), truncated, refused, unsupportedToolCall, unsupportedStopReason

    var errorDescription: String? {
        switch self {
        case .malformedEvent: return "AI 服务返回了无效的流式数据。"
        case .unexpectedEnd: return "AI 连接提前中断，回复尚未完成，请重试。"
        case .emptyResponse: return "AI 服务没有返回可用的文本。"
        case .responseTooLarge: return "AI 回复超过本次处理上限，请缩小任务后重试。"
        case .timedOut: return "AI 请求超过 120 秒，请稍后重试。"
        case .providerError(let code): return "AI 服务返回错误（\(code)），本次任务未完成。"
        case .truncated: return "AI 回复达到服务商输出限制而被截断，请缩小任务后重试。"
        case .refused: return "AI 服务拒绝了本次请求，未产生完整结果。"
        case .unsupportedToolCall: return "AI 服务返回了本次请求未启用的工具调用，无法完成此步骤。"
        case .unsupportedStopReason: return "AI 服务未正常完成回复，请重试。"
        }
    }
}

enum NexusSSEFormat { case anthropic, openAICompatible }

/// Byte framing follows WHATWG SSE: UTF-8, LF/CR/CRLF, optional single space,
/// data lines joined with LF and dispatch only at a blank line. No EOF flush.
/// Provider formats: Claude Streaming Messages and OpenAI Chat Completions.
struct NexusSSEParser {
    let format: NexusSSEFormat
    let maxResponseCharacters: Int
    let maxEventBytes: Int
    let maxWireBytes: Int
    private(set) var completed = false
    private var firstLine = true
    private var previousWasCR = false
    private var line = [UInt8]()
    private var eventName = ""
    private var dataLines = [String]()
    private var eventBytes = 0
    private var wireBytes = 0
    private var responseCharacters = 0
    private var hasVisibleText = false
    private var anthropicStarted = false
    private var blocks = [Int: String]()
    private var normalStop = false

    init(format: NexusSSEFormat, maxResponseCharacters: Int = 64_000,
         maxEventBytes: Int = 256 * 1024, maxWireBytes: Int = 4 * 1024 * 1024) {
        self.format = format
        self.maxResponseCharacters = max(1, maxResponseCharacters)
        self.maxEventBytes = max(1, maxEventBytes)
        self.maxWireBytes = max(1, maxWireBytes)
    }

    /// Returns a displayable text delta, if this byte finishes an event with text.
    mutating func consume(_ byte: UInt8) throws -> String? {
        guard !completed else { return nil }
        wireBytes += 1
        guard wireBytes <= maxWireBytes else { throw NexusStreamError.responseTooLarge }
        if byte == 10, previousWasCR { previousWasCR = false; return nil }
        previousWasCR = byte == 13
        if byte == 10 || byte == 13 { return try finishLine() }
        line.append(byte)
        guard line.count <= maxEventBytes else { throw NexusStreamError.responseTooLarge }
        return nil
    }

    func finish() throws {
        guard completed else { throw NexusStreamError.unexpectedEnd }
    }

    private mutating func finishLine() throws -> String? {
        defer { line.removeAll(keepingCapacity: true); firstLine = false }
        let bytes = firstLine && line.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(line.dropFirst(3)) : line
        guard let value = String(bytes: bytes, encoding: .utf8) else { throw NexusStreamError.malformedEvent }
        if value.isEmpty {
            let name = eventName
            let payload = dataLines.joined(separator: "\n")
            eventName = ""; dataLines.removeAll(keepingCapacity: true); eventBytes = 0
            guard !payload.isEmpty else { return nil }
            return try parseEvent(name: name, payload: payload)
        }
        if value.hasPrefix(":") { return nil }
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var content = parts.count == 2 ? String(parts[1]) : ""
        if content.hasPrefix(" ") { content.removeFirst() }
        eventBytes += bytes.count + 1
        guard eventBytes <= maxEventBytes else { throw NexusStreamError.responseTooLarge }
        switch field {
        case "data": dataLines.append(content)
        case "event": eventName = content
        default: break // id/retry and future fields do not change this single request.
        }
        return nil
    }

    private mutating func parseEvent(name: String, payload: String) throws -> String? {
        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            guard format == .openAICompatible, normalStop else { throw NexusStreamError.unexpectedEnd }
            try complete()
            return nil
        }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NexusStreamError.malformedEvent
        }
        if name == "error" || json["type"] as? String == "error" || json["error"] is [String: Any] {
            let detail = json["error"] as? [String: Any] ?? json
            let raw = detail["type"] as? String ?? detail["code"] as? String ?? "provider_error"
            // Do not echo an arbitrary provider message, which can contain request data or a key.
            let code = String(raw.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) }.prefix(60))
            throw NexusStreamError.providerError(code.isEmpty ? "provider_error" : code)
        }
        switch format {
        case .anthropic: return try parseAnthropic(name: name, json: json)
        case .openAICompatible: return try parseOpenAI(json: json)
        }
    }

    private mutating func parseAnthropic(name: String, json: [String: Any]) throws -> String? {
        guard let type = json["type"] as? String else { throw NexusStreamError.malformedEvent }
        guard name.isEmpty || name == type else { throw NexusStreamError.malformedEvent }
        if type == "ping" { return nil }
        if type == "message_start" {
            guard !anthropicStarted, json["message"] is [String: Any] else { throw NexusStreamError.malformedEvent }
            anthropicStarted = true
            return nil
        }
        guard anthropicStarted else { throw NexusStreamError.malformedEvent }
        switch type {
        case "content_block_start":
            guard !normalStop, let index = json["index"] as? Int, index >= 0, blocks[index] == nil,
                  let block = json["content_block"] as? [String: Any], let type = block["type"] as? String else {
                throw NexusStreamError.malformedEvent
            }
            if type == "tool_use" || type == "server_tool_use" { throw NexusStreamError.unsupportedToolCall }
            blocks[index] = type
            if type == "text" {
                guard let value = block["text"] as? String else { throw NexusStreamError.malformedEvent }
                return try text(value)
            }
        case "content_block_delta":
            guard !normalStop, let index = json["index"] as? Int, let blockType = blocks[index],
                  let delta = json["delta"] as? [String: Any], let deltaType = delta["type"] as? String else {
                throw NexusStreamError.malformedEvent
            }
            if deltaType == "input_json_delta" { throw NexusStreamError.unsupportedToolCall }
            if deltaType == "text_delta" {
                guard blockType == "text", let value = delta["text"] as? String else { throw NexusStreamError.malformedEvent }
                return try text(value)
            }
        case "content_block_stop":
            guard let index = json["index"] as? Int, blocks.removeValue(forKey: index) != nil else { throw NexusStreamError.malformedEvent }
        case "message_delta":
            guard let delta = json["delta"] as? [String: Any] else { throw NexusStreamError.malformedEvent }
            if let reason = delta["stop_reason"] as? String {
                switch reason {
                case "end_turn", "stop_sequence": normalStop = true
                case "max_tokens", "model_context_window_exceeded": throw NexusStreamError.truncated
                case "refusal": throw NexusStreamError.refused
                case "tool_use": throw NexusStreamError.unsupportedToolCall
                default: throw NexusStreamError.unsupportedStopReason
                }
            }
        case "message_stop":
            guard normalStop, blocks.isEmpty else { throw NexusStreamError.unexpectedEnd }
            try complete()
        default: break // Unknown event types are forward-compatible, but never imply completion.
        }
        return nil
    }

    private mutating func parseOpenAI(json: [String: Any]) throws -> String? {
        guard let choices = json["choices"] as? [[String: Any]] else { throw NexusStreamError.malformedEvent }
        if choices.isEmpty { return nil } // Optional final usage chunk.
        guard choices.count == 1, let choice = choices.first, choice["index"] as? Int == 0,
              let delta = choice["delta"] as? [String: Any] else { throw NexusStreamError.malformedEvent }
        for key in ["content", "refusal", "role"] {
            if let value = delta[key], !(value is NSNull), !(value is String) { throw NexusStreamError.malformedEvent }
        }
        if let value = choice["finish_reason"], !(value is NSNull), !(value is String) { throw NexusStreamError.malformedEvent }
        if let value = delta["tool_calls"], !(value is NSNull), !(value is [Any]) { throw NexusStreamError.malformedEvent }
        if let role = delta["role"] as? String, role != "assistant" { throw NexusStreamError.malformedEvent }
        if let calls = delta["tool_calls"] as? [Any], !calls.isEmpty { throw NexusStreamError.unsupportedToolCall }
        if delta["function_call"] is [String: Any] { throw NexusStreamError.unsupportedToolCall }
        if let refusal = delta["refusal"] as? String, !refusal.isEmpty { throw NexusStreamError.refused }
        let value = delta["content"] as? String ?? ""
        guard !normalStop || value.isEmpty else { throw NexusStreamError.malformedEvent }
        if let reason = choice["finish_reason"] as? String {
            switch reason {
            case "stop": normalStop = true
            case "length": throw NexusStreamError.truncated
            case "content_filter": throw NexusStreamError.refused
            case "tool_calls", "function_call": throw NexusStreamError.unsupportedToolCall
            default: throw NexusStreamError.unsupportedStopReason
            }
        }
        return try text(value)
    }

    private mutating func text(_ value: String) throws -> String? {
        guard !value.isEmpty else { return nil }
        responseCharacters += value.count
        guard responseCharacters <= maxResponseCharacters else { throw NexusStreamError.responseTooLarge }
        hasVisibleText = hasVisibleText || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return value
    }

    private mutating func complete() throws {
        guard hasVisibleText else { throw NexusStreamError.emptyResponse }
        completed = true
    }
}
