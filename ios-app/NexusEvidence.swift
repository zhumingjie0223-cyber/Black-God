import Foundation

/// Bound model context while retaining both leading diagnostics and final results.
enum NexusEvidence {
    static func preview(_ text: String, limit: Int = 4000) -> String {
        guard text.count > limit else { return text }
        let marker = "\n[输出过长，中间内容已截取；不能据此声称检查了全部内容]\n"
        let available = max(0, limit - marker.count)
        return String(text.prefix(available / 2)) + marker + String(text.suffix(available - available / 2))
    }
    static func summary(_ traces: [NexusToolTrace]) -> String {
        let recent = traces.suffix(12)
        let prefix = traces.count > recent.count ? "[仅展示最近12次调用，较早证据未包含]\n" : ""
        return prefix + recent.map {
            "工具 \($0.call.name)，参数 \(preview(String(describing: $0.call.arguments), limit: 300))，成功=\($0.succeeded)，实际结果：\(preview($0.result, limit: 900))"
        }.joined(separator: "\n")
    }
    static func unresolvedFailures(_ traces: [NexusToolTrace]) -> [String] {
        var latest: [String: Bool] = [:]
        for trace in traces { latest[trace.call.name] = trace.succeeded }
        return latest.filter { !$0.value }.map(\.key).sorted()
    }
}
