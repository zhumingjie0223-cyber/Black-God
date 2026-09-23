import Foundation

/// 把流式工具参数按序号拼完整。拼不完就保持未完成，调用方不得执行。
struct NexusToolCallAssembler {
    private struct Partial {
        var name = ""
        var arguments = ""
    }

    private var parts: [Int: Partial] = [:]

    mutating func append(index: Int, name: String?, arguments fragment: String?) {
        var item = parts[index] ?? Partial()
        if let name, !name.isEmpty { item.name = name }
        if let fragment { item.arguments += fragment }
        parts[index] = item
    }

    /// 没有片段时返回空数组。有片段但参数还不是完整对象时返回空。
    func completed() -> [[String: Any]]? {
        guard !parts.isEmpty else { return [] }
        var calls: [[String: Any]] = []
        for index in parts.keys.sorted() {
            let item = parts[index]!
            guard !item.name.isEmpty else { return nil }
            let arguments: [String: String]
            if item.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                arguments = [:]
            } else if let parsed = NexusToolArguments.parse(item.arguments) {
                arguments = parsed
            } else {
                return nil
            }
            calls.append(["name": item.name, "arguments": arguments])
        }
        return calls
    }
}
