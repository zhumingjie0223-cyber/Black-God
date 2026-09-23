import Foundation

/// 把服务商返回的工具参数收成字符串字典。数字、布尔和嵌套 JSON 都收成文本；半截 JSON 返回空，不执行。
enum NexusToolArguments {
    static func parse(_ value: Any?) -> [String: String]? {
        guard let value, !(value is NSNull) else { return [:] }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [:] }
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return parse(object)
        }
        guard let object = value as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, item) in object {
            guard let text = stringify(item) else { return nil }
            result[key] = text
        }
        return result
    }

    static func stringify(_ value: Any) -> String? {
        if value is NSNull { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        if let flag = value as? Bool { return flag ? "true" : "false" }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}

enum NexusToolCallText {
    static func appending(_ calls: [[String: Any]], to text: String) -> String {
        guard !calls.isEmpty, NexusToolCallParser.extract(from: text).isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: calls),
              let json = String(data: data, encoding: .utf8) else { return text }
        var output = text
        if !output.isEmpty { output += "\n" }
        output += "```json\n\(json)\n```"
        return output
    }
}

struct NexusToolCallParser {
    struct Response {
        let calls: [NexusToolCall]
        let text: String
    }

    private struct ModelCall: Decodable {
        let id: String?
        let name: String
        let arguments: [String: String]

        private struct JSONValue: Decodable {
            let value: Any
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() { value = NSNull(); return }
                if let text = try? container.decode(String.self) { value = text; return }
                if let flag = try? container.decode(Bool.self) { value = flag; return }
                if let number = try? container.decode(Double.self) { value = number; return }
                if let object = try? container.decode([String: JSONValue].self) { value = object.mapValues(\.value); return }
                if let list = try? container.decode([JSONValue].self) { value = list.map(\.value); return }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法读取工具参数")
            }
        }

        private enum CodingKeys: String, CodingKey { case id, name, arguments, function }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.function) {
                let function = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .function)
                name = try function.decode(String.self, forKey: .name)
                arguments = try Self.arguments(from: function)
                id = try container.decodeIfPresent(String.self, forKey: .id)
            } else {
                name = try container.decode(String.self, forKey: .name)
                arguments = try Self.arguments(from: container)
                id = try container.decodeIfPresent(String.self, forKey: .id)
            }
        }

        private static func arguments(from container: KeyedDecodingContainer<CodingKeys>) throws -> [String: String] {
            if let object = try? container.decode([String: JSONValue].self, forKey: .arguments),
               let parsed = NexusToolArguments.parse(object.mapValues(\.value)) {
                return parsed
            }
            let text = try container.decode(String.self, forKey: .arguments)
            guard let parsed = NexusToolArguments.parse(text) else {
                throw DecodingError.dataCorruptedError(forKey: .arguments, in: container, debugDescription: "工具参数不是完整的对象")
            }
            return parsed
        }

        var toolCall: NexusToolCall {
            NexusToolCall(id: id.flatMap(UUID.init(uuidString:)) ?? UUID(), name: name, arguments: arguments)
        }
    }

    private struct ToolEnvelope: Decodable { let toolCalls: [ModelCall]
        enum CodingKeys: String, CodingKey { case toolCalls = "tool_calls" }
    }

    static func parse(_ text: String) -> [NexusToolCall] {
        guard let data = text.data(using: .utf8) else { return [] }
        if let calls = try? JSONDecoder().decode([ModelCall].self, from: data), !calls.isEmpty { return calls.map(\.toolCall) }
        if let call = try? JSONDecoder().decode(ModelCall.self, from: data), !call.name.isEmpty { return [call.toolCall] }
        if let envelope = try? JSONDecoder().decode(ToolEnvelope.self, from: data), !envelope.toolCalls.isEmpty {
            return envelope.toolCalls.map(\.toolCall)
        }
        return []
    }

    static func extract(from text: String) -> [NexusToolCall] {
        response(from: text).calls
    }

    /// 统一解析整个 JSON 与完整代码块，保留普通代码展示。
    static func response(from text: String) -> Response {
        let directCalls = parse(text)
        if !directCalls.isEmpty { return Response(calls: directCalls, text: "") }

        let pattern = #"(?ms)^[\t ]*```(?:json)?[\t ]*\r?\n(.*?)^[\t ]*```[\t ]*(?:\r?\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return Response(calls: [], text: text)
        }
        var calls: [NexusToolCall] = []
        var visible = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text),
                  let contentRange = Range(match.range(at: 1), in: text) else { continue }
            let blockCalls = parse(String(text[contentRange]))
            guard !blockCalls.isEmpty else { continue }
            visible += text[cursor..<range.lowerBound]
            cursor = range.upperBound
            calls += blockCalls
        }
        visible += text[cursor...]
        return Response(calls: calls, text: visible.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
