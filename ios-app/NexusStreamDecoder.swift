import Foundation

/// 按事件边界解析 SSE；支持字节分片、中文、多行 data 和 CRLF。
struct NexusSSEDecoder {
    private var line = Data()
    private var dataLines: [String] = []
    private var eventBytes = 0
    mutating func append(_ byte: UInt8) throws -> String? {
        if byte != 10 {
            guard line.count < 262144 else { throw NexusError.apiError("服务商返回的单行响应过大。") }
            line.append(byte)
            return nil
        }
        if line.last == 13 { line.removeLast() }
        guard let text = String(data: line, encoding: .utf8) else { throw NexusError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        return try consume(text)
    }
    private mutating func consume(_ text: String) throws -> String? {
        if text.isEmpty {
            defer { dataLines.removeAll(); eventBytes = 0 }
            return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
        }
        guard text.hasPrefix("data:") else { return nil }
        var value = String(text.dropFirst(5))
        if value.hasPrefix(" ") { value.removeFirst() }
        eventBytes += value.utf8.count
        guard eventBytes <= 524288 else { throw NexusError.apiError("服务商返回的事件过大。") }
        dataLines.append(value)
        return nil
    }
    mutating func finish() throws -> String? {
        if !line.isEmpty {
            if line.last == 13 { line.removeLast() }
            guard let text = String(data: line, encoding: .utf8) else { throw NexusError.invalidResponse }
            _ = try consume(text)
            line.removeAll()
        }
        return try consume("")
    }
}

struct NexusStreamContent {
    let providerType: NexusProviderType
    private(set) var completed = false
    private(set) var output = ""
    private var sawFinish = false
    private var sawToolFinish = false
    private var tools = NexusToolCallAssembler()
    init(providerType: NexusProviderType) { self.providerType = providerType }

    mutating func receive(_ payload: String) throws -> String? {
        if payload == "[DONE]" {
            guard providerType == .openAICompatible else { throw NexusError.invalidResponse }
            completed = true
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw NexusError.apiError("服务商返回了无效的流式数据。")
        }
        if let error = object["error"] as? [String: Any] {
            throw NexusError.apiError(error["message"] as? String ?? "服务商在生成过程中报错。")
        }
        var text: String?
        switch providerType {
        case .gemini, .responses: throw NexusError.invalidResponse
        case .anthropic:
            let type = object["type"] as? String
            if type == "content_block_delta", let delta = object["delta"] as? [String: Any], delta["type"] as? String == "text_delta" {
                text = delta["text"] as? String
            }
            if type == "content_block_start", let block = object["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                let index = object["index"] as? Int ?? 0
                tools.append(index: index, name: block["name"] as? String, arguments: nil)
            }
            if type == "content_block_delta", let delta = object["delta"] as? [String: Any], delta["type"] as? String == "input_json_delta" {
                let index = object["index"] as? Int ?? 0
                tools.append(index: index, name: nil, arguments: delta["partial_json"] as? String)
            }
            if type == "message_delta", let delta = object["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                if reason == "tool_use" { sawToolFinish = true; sawFinish = true }
                else { try validateFinish(reason); sawFinish = true }
            }
            if type == "message_stop" { completed = true }
        case .openAICompatible:
            if let choices = object["choices"] as? [[String: Any]], let choice = choices.first {
                if let delta = choice["delta"] as? [String: Any] {
                    if let calls = delta["tool_calls"] as? [[String: Any]] {
                        for call in calls {
                            let index = (call["index"] as? NSNumber)?.intValue ?? 0
                            let function = call["function"] as? [String: Any]
                            tools.append(index: index, name: function?["name"] as? String, arguments: function?["arguments"] as? String)
                        }
                    }
                    text = delta["content"] as? String ?? delta["refusal"] as? String
                }
                if let reason = choice["finish_reason"] as? String {
                    if reason == "tool_calls" { sawToolFinish = true; sawFinish = true }
                    else { try validateFinish(reason); sawFinish = true }
                }
            }
        }
        if let text {
            guard output.utf8.count + text.utf8.count <= 2_000_000 else { throw NexusError.apiError("回答超过本机接收上限。") }
            output += text
        }
        return text
    }
    mutating func receiveJSON(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NexusError.invalidResponse }
        if let error = object["error"] as? [String: Any] { throw NexusError.apiError(error["message"] as? String ?? "服务商返回错误。") }
        switch providerType {
        case .gemini, .responses: throw NexusError.invalidResponse
        case .openAICompatible:
            guard let choice = (object["choices"] as? [[String: Any]])?.first,
                  let message = choice["message"] as? [String: Any] else { throw NexusError.invalidResponse }
            let reason = choice["finish_reason"] as? String
            if reason == "length" || reason == "content_filter" { try validateFinish(reason ?? "") }
            var calls: [[String: Any]] = []
            if let rawCalls = message["tool_calls"] as? [[String: Any]] {
                for item in rawCalls {
                    guard let function = item["function"] as? [String: Any],
                          let name = function["name"] as? String, !name.isEmpty,
                          let arguments = NexusToolArguments.parse(function["arguments"]) else {
                        throw NexusError.apiError("工具参数不完整，尚未执行。")
                    }
                    calls.append(["name": name, "arguments": arguments])
                }
            }
            if reason == "tool_calls", calls.isEmpty { throw NexusError.apiError("模型声称要调用工具，但没有给出完整调用，尚未执行。") }
            output = NexusToolCallText.appending(calls, to: message["content"] as? String ?? message["refusal"] as? String ?? "")
        case .anthropic:
            guard let blocks = object["content"] as? [[String: Any]], let reason = object["stop_reason"] as? String else { throw NexusError.invalidResponse }
            if reason == "max_tokens" { try validateFinish(reason) }
            var calls: [[String: Any]] = []
            for block in blocks where block["type"] as? String == "tool_use" {
                guard let name = block["name"] as? String, !name.isEmpty,
                      let arguments = NexusToolArguments.parse(block["input"]) else {
                    throw NexusError.apiError("工具参数不完整，尚未执行。")
                }
                calls.append(["name": name, "arguments": arguments])
            }
            if reason == "tool_use", calls.isEmpty { throw NexusError.apiError("模型声称要调用工具，但没有给出完整调用，尚未执行。") }
            if calls.isEmpty { try validateFinish(reason) }
            output = NexusToolCallText.appending(calls, to: blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined())
        }
        completed = true
        try validateEnd()
        return output
    }

    private func validateFinish(_ reason: String) throws {
        switch reason {
        case "stop", "end_turn", "stop_sequence", "refusal": return
        case "length", "max_tokens": throw NexusError.apiError("回答达到服务商输出长度上限，尚未完整生成。请缩小问题后重试。")
        case "content_filter": throw NexusError.apiError("服务商终止了本次生成（内容过滤）。")
        default: throw NexusError.apiError("服务商未正常完成回答（\(reason)）。")
        }
    }
    mutating func validateEnd() throws {
        guard completed || sawFinish else { throw NexusError.apiError("连接在回答完成前中断，请重试。") }
        switch tools.completed() {
        case nil:
            throw NexusError.apiError("工具参数不完整，尚未执行。")
        case let calls?:
            if sawToolFinish, calls.isEmpty {
                throw NexusError.apiError("模型声称要调用工具，但没有给出完整调用，尚未执行。")
            }
            output = NexusToolCallText.appending(calls, to: output)
        }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NexusError.invalidResponse }
    }
}
