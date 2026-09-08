import Foundation

struct NexusToolCallParser {
    struct Response {
        let calls: [NexusToolCall]
        let text: String
    }

    private struct ModelCall: Decodable {
        let id: String?
        let name: String
        let arguments: [String: Argument]

        struct Argument: Decodable {
            let text: String
            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let string = try? value.decode(String.self) { text = string }
                else if let number = try? value.decode(Double.self) { text = NSNumber(value: number).stringValue }
                else if let boolean = try? value.decode(Bool.self) { text = boolean ? "true" : "false" }
                else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "工具参数必须是文本、数字或布尔值") }
            }
        }

        var toolCall: NexusToolCall {
            NexusToolCall(id: id.flatMap(UUID.init(uuidString:)) ?? UUID(), name: name, arguments: arguments.mapValues(\.text))
        }
    }

    static func parse(_ text: String) -> [NexusToolCall] {
        guard let data = text.data(using: .utf8) else { return [] }
        if let calls = try? JSONDecoder().decode([ModelCall].self, from: data) { return calls.map(\.toolCall) }
        if let call = try? JSONDecoder().decode(ModelCall.self, from: data) { return [call.toolCall] }
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
