import Foundation

/// Source identifiers come from retrieval unchanged; tool identifiers come from call UUIDs.
struct NexusEvidenceReference: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case memory, file, taskSummary, web }
    let id: String
    let kind: Kind
    let label: String
    let verified: Bool

    init(id: String, kind: Kind, label: String, verified: Bool = false) {
        self.id = id; self.kind = kind; self.label = label; self.verified = verified
    }
}

/// A portable view of an observed tool result. A model answer cannot create one.
struct NexusEvidenceRecord: Codable, Equatable, Identifiable {
    let id: String
    let stepID: UUID
    let tool: String
    let succeeded: Bool
    let output: String
    let authorizationDenied: Bool
    let scope: String?

    init(id: String, stepID: UUID, tool: String, succeeded: Bool, output: String,
         authorizationDenied: Bool = false, scope: String? = nil) {
        self.id = id; self.stepID = stepID; self.tool = tool; self.succeeded = succeeded
        self.output = output; self.authorizationDenied = authorizationDenied
        self.scope = scope
    }
}

/// Requirements are compiled from the task, never from a model's declaration of completion.
struct NexusEvidenceRequirement: Codable, Equatable, Identifiable {
    let id: String
    let description: String
    let toolName: String?
    let evidenceIDs: [String]
    let expectedOutput: String?
    let requiresSuccessfulTool: Bool
    let requiresVerifiedSource: Bool

    init(id: String, description: String, toolName: String? = nil, evidenceIDs: [String] = [],
         expectedOutput: String? = nil, requiresSuccessfulTool: Bool = true,
         requiresVerifiedSource: Bool = false) {
        self.id = id; self.description = description; self.toolName = toolName
        self.evidenceIDs = evidenceIDs; self.expectedOutput = expectedOutput
        self.requiresSuccessfulTool = requiresSuccessfulTool
        self.requiresVerifiedSource = requiresVerifiedSource
    }
}

struct NexusEvidenceAuditReport: Equatable {
    let slotsComplete: Bool
    let evidenceConsistent: Bool
    let authorized: Bool
    let issues: [String]
    var passed: Bool { slotsComplete && evidenceConsistent && authorized }
}

/// 调用成功与取得资料是两件事；状态只核对工具输出结构，不认证任意自然语言事实。
enum NexusRetrievalEvidenceStatus: Equatable {
    case notRetrieval, matched, empty, invalid
}

/// Three bounded checks: filled slots, conclusions supported by evidence, and authorization.
/// This verifies observed requirements; it does not certify arbitrary real-world assertions.
enum NexusEvidenceAudit {
    static func toolID(_ callID: UUID) -> String { "tool:" + callID.uuidString.lowercased() }

    /// 只识别各检索工具实际产出的协议；任意一段文字不能充当召回证据。
    static func retrievalStatus(tool: String, output: String) -> NexusRetrievalEvidenceStatus {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        switch tool {
        case "memory_search":
            if text == "没有检索到相关用户记录，不要编造记忆。" { return .empty }
            if let object = jsonObject(text), object["retrievalTool"] as? String == tool {
                guard object["status"] as? String == "no_matches", object["count"] as? Int == 0,
                      object["message"] as? String == "没有检索到相关用户记录，不要编造记忆。",
                      object["candidates"] == nil, object["sourceID"] == nil,
                      object["evidenceID"] == nil else { return .invalid }
                return .empty
            }
            let matches = text.components(separatedBy: .newlines).compactMap(jsonObject).filter { candidate in
                guard let id = candidate["id"] as? String, id.hasPrefix("memory:"),
                      UUID(uuidString: String(id.dropFirst("memory:".count))) != nil,
                      candidate["source"] as? String == "confirmedMemory",
                      candidate["isConfirmed"] as? Bool == true, candidate["isGenerated"] as? Bool != true,
                      let body = candidate["text"] as? String,
                      !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                return true
            }
            guard !matches.isEmpty else { return .invalid }
            // 近期先验帮助编译器消歧，但没有词面或向量命中，不能支持偏好事实。
            return matches.contains(where: { $0["retrievalMethod"] as? String != "recency" }) ? .matched : .empty
        case "skill_search":
            if text == "没有匹配技能，不要编造技能。" ||
                text == "当前没有可用技能；历史中的已删除技能不应继续引用。" { return .empty }
            // 兼容现有目录格式；目录头和带有效 UUID、版本号的行须同时存在。
            guard text.hasPrefix("当前技能目录（共"),
                  let row = try? NSRegularExpression(pattern: "(?m)^ID=([0-9A-Fa-f-]{36})，版本=([1-9][0-9]*)，名称="),
                  row.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains(where: { match in
                      guard let range = Range(match.range(at: 1), in: text) else { return false }
                      return UUID(uuidString: String(text[range])) != nil
                  }) else { return .invalid }
            return .matched
        case "web_lookup":
            guard let object = jsonObject(text), let source = object["sourceURL"] as? String,
                  let url = URL(string: source), url.scheme?.lowercased() == "https", url.host != nil,
                  object["sourceID"] as? String == "url:" + source,
                  let matched = object["matched"] as? Bool,
                  let snippets = object["snippets"] as? [String] else { return .invalid }
            let hasText = snippets.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !hasText { return .empty }
            return matched ? .matched : .invalid
        default:
            return .notRetrieval
        }
    }

    /// 空检索的程序弃答；执行入口可直接使用，防止模型在提示后夹带猜测。
    static func emptyRetrievalMessage(tool: String) -> String? {
        switch tool {
        case "memory_search": return "没有检索到相关用户记录；目前没有依据判断你的偏好或补充用户事实。"
        case "skill_search": return "没有检索到匹配的已保存技能；目前无法依据技能目录提供对应流程。"
        case "web_lookup": return "指定页面没有检索到匹配内容；目前没有可引用的相关网页片段。"
        default: return nil
        }
    }

    static func review(missingSlots: [String] = [], answer: String,
                       records: [NexusEvidenceRecord], references: [NexusEvidenceReference] = [],
                       requirements: [NexusEvidenceRequirement] = [],
                       referencedEvidenceIDs: [String] = [], allowedTools: Set<String>? = nil) -> NexusEvidenceAuditReport {
        var slotIssues = missingSlots.map { "槽未填满：" + $0 }
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            slotIssues.append("未产生可交付的答复。")
        }
        var evidenceIssues: [String] = []
        var authorizationIssues: [String] = []
        let knownIDs = Set(records.map(\.id) + references.map(\.id))
        for id in Set(referencedEvidenceIDs).subtracting(knownIDs).sorted() {
            evidenceIssues.append("证据引用不存在：" + id)
        }
        // A later result supersedes an earlier failure only for the same tool and action object.
        // A success on file B cannot conceal a failed operation on file A. Denials remain visible.
        var latest: [String: NexusEvidenceRecord] = [:]
        for record in records {
            latest[record.tool + "|" + (record.scope ?? "")] = record
            if record.authorizationDenied || (allowedTools.map { !$0.contains(record.tool) } ?? false) {
                authorizationIssues.append("工具调用越权或已被拦截：\(record.tool)（\(record.id)）")
            }
        }
        for failed in latest.values.filter({ !$0.succeeded }).sorted(by: {
            ($0.tool + "|" + ($0.scope ?? "") + "|" + $0.id) < ($1.tool + "|" + ($1.scope ?? "") + "|" + $1.id)
        }) {
            evidenceIssues.append("工具最后一次调用未成功：\(failed.tool)（\(failed.id)）")
        }
        for record in latest.values.filter({ $0.succeeded && !$0.authorizationDenied }).sorted(by: { $0.id < $1.id }) {
            switch retrievalStatus(tool: record.tool, output: record.output) {
            case .empty:
                evidenceIssues.append("检索调用已完成，但未取得可引用的匹配资料：\(record.tool)（\(record.id)）")
            case .invalid:
                evidenceIssues.append("检索输出没有可核对的候选或片段：\(record.tool)（\(record.id)）")
            case .matched, .notRetrieval:
                break
            }
        }
        let nonExecutingTools: Set<String> = ["plan", "verify", "knowledge_propose"]
        for requirement in requirements {
            let selected = records.filter { record in
                (requirement.toolName == nil || requirement.toolName == record.tool) &&
                (requirement.evidenceIDs.isEmpty || requirement.evidenceIDs.contains(record.id))
            }
            let missing = Set(requirement.evidenceIDs).subtracting(knownIDs)
            if !missing.isEmpty {
                evidenceIssues.append("条件「\(requirement.description)」引用缺失证据：" + missing.sorted().joined(separator: "、"))
            }
            if requirement.requiresSuccessfulTool && !selected.contains(where: {
                $0.succeeded && !$0.authorizationDenied && !nonExecutingTools.contains($0.tool) && hasSupportingResult($0)
            }) {
                let retrievalExecuted = selected.contains { $0.succeeded && !$0.authorizationDenied &&
                    retrievalStatus(tool: $0.tool, output: $0.output) != .notRetrieval }
                evidenceIssues.append("条件「\(requirement.description)」" +
                    (retrievalExecuted ? "检索已执行，但未取得可引用的匹配资料。" : "缺少成功工具证据。"))
            }
            if let expected = requirement.expectedOutput {
                let expectedValue = expected.trimmingCharacters(in: .whitespacesAndNewlines)
                if !selected.contains(where: { $0.succeeded && outputsMatch($0.output, expectedValue) }) {
                    evidenceIssues.append("条件「\(requirement.description)」与实际工具结果不一致。")
                }
            }
            if requirement.requiresVerifiedSource && !references.contains(where: {
                $0.verified && requirement.evidenceIDs.contains($0.id)
            }) {
                evidenceIssues.append("条件「\(requirement.description)」缺少已核对的来源。")
            }
        }
        let actualActions = records.filter { $0.succeeded && !$0.authorizationDenied && !nonExecutingTools.contains($0.tool) && hasSupportingResult($0) }
        if claimsCompletedAction(answer), actualActions.isEmpty {
            evidenceIssues.append("答复宣称动作已完成，但没有成功工具证据。")
        }
        let actionClaims: [([String], Set<String>)] = [
            (["已删除", "删除成功"], ["workspace_delete", "shell_execute"]),
            (["已发送", "发送成功"], ["send_message", "send_email"]),
            (["已付款", "支付成功"], ["payment", "purchase"]),
            (["已写入", "已保存", "已修改"], ["workspace_write", "write_file", "shell_execute"]),
            (["已移动"], ["workspace_move", "shell_execute"]),
            (["已恢复", "恢复成功"], ["workspace_restore"])
        ]
        for (markers, tools) in actionClaims where containsUnnegatedClaim(answer, markers: markers) {
            if !actualActions.contains(where: { tools.contains($0.tool) }) {
                evidenceIssues.append("完成声明缺少对应操作工具证据：" + markers[0])
            }
        }
        // A required calculator result must be represented in the answer; model confidence is irrelevant.
        for requirement in requirements where requirement.toolName == "calc" && requirement.requiresSuccessfulTool {
            let calculations = records.filter { $0.tool == "calc" && $0.succeeded &&
                (requirement.evidenceIDs.isEmpty || requirement.evidenceIDs.contains($0.id)) }
            if let result = calculations.last?.output.trimmingCharacters(in: .whitespacesAndNewlines),
               let number = Double(result), !containsConfirmedNumber(number, in: answer) {
                evidenceIssues.append("计算结论未包含工具确认的结果：\(result)。")
            }
        }
        return NexusEvidenceAuditReport(slotsComplete: slotIssues.isEmpty,
            evidenceConsistent: evidenceIssues.isEmpty, authorized: authorizationIssues.isEmpty,
            issues: slotIssues + evidenceIssues + authorizationIssues)
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    private static func hasSupportingResult(_ record: NexusEvidenceRecord) -> Bool {
        switch retrievalStatus(tool: record.tool, output: record.output) {
        case .matched, .notRetrieval: return true
        case .empty, .invalid: return false
        }
    }

    private static func claimsCompletedAction(_ answer: String) -> Bool {
        let markers = ["已经完成", "已完成", "完成了", "处理好了", "已执行", "执行成功", "已删除", "删除成功",
                       "已发送", "发送成功", "已付款", "支付成功", "已写入", "已保存", "已修改", "已移动", "已恢复", "恢复成功"]
        return containsUnnegatedClaim(answer, markers: markers)
    }

    private static func outputsMatch(_ observed: String, _ expected: String) -> Bool {
        let value = observed.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = Double(value), let b = Double(expected), a.isFinite, b.isFinite { return a == b }
        return value == expected
    }

    private static func containsConfirmedNumber(_ number: Double, in answer: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: "(?<![0-9.])[-+]?[0-9]+(?:\\.[0-9]+)?(?:[eE][-+]?[0-9]+)?(?![0-9.])") else { return false }
        for match in expression.matches(in: answer, range: NSRange(answer.startIndex..., in: answer)) {
            guard let range = Range(match.range, in: answer), Double(answer[range]) == number else { continue }
            let start = answer.index(range.lowerBound, offsetBy: -5, limitedBy: answer.startIndex) ?? answer.startIndex
            let before = String(answer[start..<range.lowerBound])
            if !["不是", "不等于", "并非", "错误的"].contains(where: before.hasSuffix) { return true }
        }
        return false
    }

    private static func containsUnnegatedClaim(_ answer: String, markers: [String]) -> Bool {
        for marker in markers {
            var cursor = answer.startIndex
            while let range = answer.range(of: marker, range: cursor..<answer.endIndex) {
                let start = answer.index(range.lowerBound, offsetBy: -10, limitedBy: answer.startIndex) ?? answer.startIndex
                let before = String(answer[start..<range.lowerBound])
                let negations = ["未", "没有", "不能", "无法", "尚未", "不代表", "不保证", "是否", "假称", "声称", "不能声称", "没有证据证明"]
                if !negations.contains(where: before.hasSuffix) {
                    return true
                }
                cursor = range.upperBound
            }
        }
        return false
    }
}
