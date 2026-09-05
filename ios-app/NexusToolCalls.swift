import Foundation

/// 解析模型文本输出里的工具调用。约定：模型输出 ```tool（或 ```json）代码块，
/// 内容为 `{"name": "工具名", "arguments": {"键": "值"}}`。同时兼容整段就是该 JSON 的情况。
struct NexusToolCallParser {
    private static let fenceTags = ["tool", "json"]

    static func parse(_ text: String) -> [NexusToolCall] {
        var calls: [NexusToolCall] = []
        for block in fencedBlocks(in: text) {
            calls.append(contentsOf: decode(block))
        }
        if calls.isEmpty {
            calls.append(contentsOf: decode(text))
        }
        return calls
    }

    /// 供 Runtime 侧沿用的别名。
    static func extract(from text: String) -> [NexusToolCall] { parse(text) }

    /// 从输出里剔除所有 ```tool / ```json 代码块，得到面向用户的正文。
    static func stripCalls(from text: String) -> String {
        var result = text
        for tag in fenceTags {
            result = removeFences(tag: tag, from: result)
        }
        return result
    }

    // MARK: - 私有

    private static func fencedBlocks(in text: String) -> [String] {
        var blocks: [String] = []
        for tag in fenceTags {
            let opener = "```\(tag)"
            var searchStart = text.startIndex
            while let open = text.range(of: opener, range: searchStart..<text.endIndex) {
                guard let close = text.range(of: "```", range: open.upperBound..<text.endIndex) else { break }
                blocks.append(String(text[open.upperBound..<close.lowerBound]))
                searchStart = close.upperBound
            }
        }
        return blocks
    }

    private static func removeFences(tag: String, from text: String) -> String {
        var result = text
        let opener = "```\(tag)"
        while let open = result.range(of: opener) {
            guard let close = result.range(of: "```", range: open.upperBound..<result.endIndex) else { break }
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result
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
            return array.compactMap(callFromObject)
        }
        return []
    }

    private static func callFromObject(_ object: [String: Any]) -> NexusToolCall? {
        guard let name = object["name"] as? String, !name.isEmpty else { return nil }
        let id = (object["id"] as? String).flatMap(UUID.init) ?? UUID()
        var arguments: [String: String] = [:]
        if let rawArgs = object["arguments"] as? [String: Any] {
            for (key, value) in rawArgs { arguments[key] = stringify(value) }
        }
        return NexusToolCall(id: id, name: name, arguments: arguments)
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let n as NSNumber: return n.stringValue
        default: return "\(value)"
        }
    }
}
