import Foundation

/// Direct REST adapters. Tool responses are complete JSON; no partial call executes.
enum NexusAdditionalProtocols {
    static func body(model: NexusModelEntry, messages: [NexusNativeMessage], tools: [NexusToolDefinition]) throws -> Data {
        var wire: [[String: Any]] = []
        for message in messages {
            switch message {
            case .text(let role, let content):
                guard ["user", "assistant"].contains(role) else { throw NexusError.invalidResponse }
                if model.providerType == .gemini {
                    wire.append(["role": role == "assistant" ? "model" : "user", "parts": [["text": content]]])
                } else { wire.append(["role": role, "content": content]) }
            case .assistant(let reply):
                if model.providerType == .gemini { wire.append(reply.assistant) }
                else {
                    guard let output = reply.assistant["output"] as? [[String: Any]] else { throw NexusError.invalidResponse }
                    wire += output // Preserve reasoning/encrypted items and opaque call IDs.
                }
            case .results(let results):
                if model.providerType == .gemini {
                    let parts: [[String: Any]] = results.map { native, result in
                        var response: [String: Any] = ["name": native.call.name,
                            "response": [result.succeeded ? "output" : "error": result.output]]
                        if native.hasProviderID { response["id"] = native.providerID }
                        return ["functionResponse": response]
                    }
                    wire.append(["role": "user", "parts": parts])
                } else {
                    wire += results.map { ["type": "function_call_output", "call_id": $0.0.providerID,
                        "output": ($0.1.succeeded ? "" : "工具失败：") + $0.1.output] }
                }
            }
        }
        guard !wire.isEmpty else { throw NexusError.invalidResponse }
        var body: [String: Any]
        if model.providerType == .gemini {
            body = ["contents": wire]
            if !tools.isEmpty {
                body["tools"] = [["functionDeclarations": try tools.map { tool -> [String: Any] in
                    // Gemini's Schema supports a subset of JSON Schema.
                    var schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tool.inputSchema)) as! [String: Any]
                    schema.removeValue(forKey: "additionalProperties")
                    return ["name": tool.name, "description": tool.description, "parameters": schema]
                }]]
            }
        } else {
            body = ["model": model.modelID, "input": wire, "stream": false, "store": false,
                    "include": ["reasoning.encrypted_content"]]
            if !tools.isEmpty {
                body["tools"] = try tools.map { tool -> [String: Any] in
                    let schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tool.inputSchema))
                    return ["type": "function", "name": tool.name, "description": tool.description,
                            "parameters": schema, "strict": false]
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        guard data.count <= 1_000_000 else { throw NexusError.apiError("工具上下文超过请求上限。") }
        return data
    }

    static func decode(_ data: Data, type: NexusProviderType) throws -> NexusNativeReply {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] == nil || object["error"] is NSNull else { throw NexusError.invalidResponse }
        var calls: [NexusNativeCall] = []
        var ids = Set<String>()
        var text = ""
        let assistant: [String: Any]
        func add(id: Any?, name: Any?, args: Any?, optionalID: Bool = false) throws {
            let provided = id as? String
            let identifier = provided ?? (optionalID ? UUID().uuidString : "")
            guard !identifier.isEmpty, identifier.utf8.count <= 512, ids.insert(identifier).inserted,
                  let name = name as? String, !name.isEmpty,
                  let args = args as? [String: String], calls.count < 8 else { throw NexusError.invalidResponse }
            calls.append(NexusNativeCall(providerID: identifier,
                call: NexusToolCall(id: UUID(), name: name, arguments: args), hasProviderID: provided != nil))
        }
        if type == .gemini {
            guard let candidates = object["candidates"] as? [[String: Any]], candidates.count == 1,
                  candidates[0]["finishReason"] as? String == "STOP",
                  let content = candidates[0]["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                throw NexusError.apiError("Gemini 响应未完成或被拦截，尚未执行工具。")
            }
            for part in parts {
                if let function = part["functionCall"] as? [String: Any] {
                    try add(id: function["id"], name: function["name"], args: function["args"] ?? [:], optionalID: true)
                }
                if part["thought"] as? Bool != true, let value = part["text"] as? String { text += value }
            }
            var replay = content
            replay["role"] = "model"
            assistant = replay // Preserve thoughtSignature fields verbatim, in memory only.
        } else {
            guard object["status"] as? String == "completed",
                  let output = object["output"] as? [[String: Any]] else {
                throw NexusError.apiError("Responses 请求未完成，尚未执行工具。")
            }
            for item in output {
                switch item["type"] as? String {
                case "function_call":
                    guard let raw = item["arguments"] as? String else { throw NexusError.invalidResponse }
                    try add(id: item["call_id"], name: item["name"], args: JSONSerialization.jsonObject(with: Data(raw.utf8)))
                case "message":
                    guard let content = item["content"] as? [[String: Any]] else { throw NexusError.invalidResponse }
                    for part in content {
                        if part["type"] as? String == "output_text" { text += part["text"] as? String ?? "" }
                        if part["type"] as? String == "refusal" { text += part["refusal"] as? String ?? "" }
                    }
                case "reasoning": break
                default: throw NexusError.apiError("Responses 返回了未开放的工具类型。")
                }
            }
            assistant = ["output": output]
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else { throw NexusError.invalidResponse }
        return NexusNativeReply(text: text, calls: calls, assistant: assistant)
    }
}
