import Foundation

/// 把流式工具参数按序号拼完整。拼不完就保持未完成，调用方不得执行。
struct NexusToolCallAssembler {
    private struct Partial {
        var name = ""
        var arguments = ""
    }

    private var parts: [Int: Partial] = [:]
    private(set) var byteCount = 0

    mutating func append(index: Int, name: String?, arguments fragment: String?) throws {
        guard index >= 0, parts[index] != nil || parts.count < NexusToolCallLimits.count else {
            throw NexusError.apiError("模型返回了无效或过多的工具调用，尚未执行。")
        }
        var item = parts[index] ?? Partial()
        let suppliedName = name.flatMap { $0.isEmpty ? nil : $0 }
        let nextBytes = byteCount + (fragment?.utf8.count ?? 0)
            + (suppliedName?.utf8.count ?? item.name.utf8.count) - item.name.utf8.count
        guard nextBytes <= NexusToolCallLimits.payloadBytes else {
            throw NexusError.apiError("模型工具参数超过接收上限，尚未执行。")
        }
        if let suppliedName { item.name = suppliedName }
        if let fragment { item.arguments += fragment }
        parts[index] = item
        byteCount = nextBytes
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
