import Foundation
import CoreFoundation

/// 解析模型文本输出里的工具调用。约定：模型输出 ```tool（或 ```json）代码块，
/// 内容为 `{"name": "工具名", "arguments": {"键": "值"}}`。同时兼容整段就是该 JSON 的情况。
struct NexusToolCallParser {
    static func parse(_ text: String) -> [NexusToolCall] {
        response(from: text).calls
    }

    /// 供 Runtime 侧沿用的别名。
    static func extract(from text: String) -> [NexusToolCall] { parse(text) }

    /// 只剔除已识别的工具调用；保留普通 JSON 示例与无法解析的代码块。
    static func stripCalls(from text: String) -> String {
        response(from: text).text
    }

    // MARK: - 私有

    private static func response(from text: String) -> (calls: [NexusToolCall], text: String) {
        let direct = decode(text)
        if !direct.isEmpty { return (direct, "") }

        let pattern = #"(?ms)^[\t ]*```(?:tool|json)[\t ]*\r?\n(.*?)^[\t ]*```[\t ]*(?:\r?\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ([], text)
        }
        var calls: [NexusToolCall] = []
        var visible = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text),
                  let contentRange = Range(match.range(at: 1), in: text) else { continue }
            let blockCalls = decode(String(text[contentRange]))
            guard !blockCalls.isEmpty else { continue }
            visible += text[cursor..<range.lowerBound]
            cursor = range.upperBound
            calls += blockCalls
        }
        visible += text[cursor...]
        return (calls, visible)
    }

    /// 解码单个 JSON 片段。支持三种形态：
    /// - `{"name": ..., "arguments": {...}}`（推荐）
    /// - `{"id": ..., "name": ..., "arguments": {...}}`（含 id）
    /// - 上述对象的数组
    private static func decode(_ fragment: String) -> [NexusToolCall] {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }

        if let object = json as? [String: Any] {
            return callFromObject(object).map { [$0] } ?? []
        }
        if let array = json as? [[String: Any]] {
            let calls = array.compactMap(callFromObject)
            return calls.count == array.count ? calls : []
        }
        return []
    }

    private static func callFromObject(_ object: [String: Any]) -> NexusToolCall? {
        guard let name = object["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rawArgs = object["arguments"] as? [String: Any] else { return nil }
        let id = (object["id"] as? String).flatMap(UUID.init) ?? UUID()
        var arguments: [String: String] = [:]
        for (key, value) in rawArgs { arguments[key] = stringify(value) }
        return NexusToolCall(id: id, name: name, arguments: arguments)
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        default: return "\(value)"
        }
    }
}
