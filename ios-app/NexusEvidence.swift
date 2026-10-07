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
            "证据 \(NexusEvidenceAudit.toolID($0.call.id))，步骤 \($0.stepID)，工具 \($0.call.name)，参数 \(preview(String(describing: $0.call.arguments), limit: 300))，成功=\($0.succeeded)，越权拦截=\($0.authorizationDenied)，实际结果：\(preview($0.result, limit: 900))"
        }.joined(separator: "\n")
    }
    static func records(_ traces: [NexusToolTrace]) -> [NexusEvidenceRecord] {
        traces.map { trace in
            let scope = ["path", "recipient", "to", "object_id", "url"].compactMap { key in
                trace.call.arguments[key].map { key + "=" + $0 }
            }.joined(separator: "|")
            return NexusEvidenceRecord(id: NexusEvidenceAudit.toolID(trace.call.id), stepID: trace.stepID,
                tool: trace.call.name, succeeded: trace.succeeded, output: trace.result,
                authorizationDenied: trace.authorizationDenied, scope: scope.isEmpty ? nil : scope)
        }
    }
    static func sourceReferences(in result: String) -> [NexusEvidenceReference] {
        let objects: [Any]
        if let object = try? JSONSerialization.jsonObject(with: Data(result.utf8)) { objects = [object] }
        else {
            // memory_search emits a trusted header followed by one JSON candidate per line.
            objects = result.components(separatedBy: .newlines).compactMap {
                try? JSONSerialization.jsonObject(with: Data($0.utf8))
            }
        }
        var references: [NexusEvidenceReference] = []
        func visit(_ value: Any) {
            if let array = value as? [Any] { array.forEach(visit); return }
            guard let dictionary = value as? [String: Any] else { return }
            let candidateID = dictionary["source"] as? String == "confirmedMemory" &&
                dictionary["isConfirmed"] as? Bool == true && dictionary["isGenerated"] as? Bool != true ? dictionary["id"] : nil
            if let id = (dictionary["sourceID"] ?? dictionary["evidenceID"] ?? candidateID) as? String {
                let kind: NexusEvidenceReference.Kind = id.hasPrefix("url:") ? .web :
                    (id.hasPrefix("memory:") ? .memory : (id.hasPrefix("task:") ? .taskSummary : .file))
                references.append(NexusEvidenceReference(id: id, kind: kind,
                    label: dictionary["sourceURL"] as? String ?? dictionary["label"] as? String ?? dictionary["title"] as? String ?? id,
                    verified: (dictionary["verified"] as? Bool == true || candidateID != nil) && kind != .web))
            }
            dictionary.values.forEach(visit)
        }
        objects.forEach(visit)
        return references
    }
    static func chips(_ traces: [NexusToolTrace], limit: Int = 6) -> [String] {
        traces.suffix(limit).map { "\($0.call.name)\($0.succeeded ? "通过" : "失败")" }
    }
    static func unresolvedFailures(_ traces: [NexusToolTrace]) -> [String] {
        var latest: [String: Bool] = [:]
        for trace in traces { latest[trace.call.name] = trace.succeeded }
        return latest.filter { !$0.value }.map(\.key).sorted()
    }
}
