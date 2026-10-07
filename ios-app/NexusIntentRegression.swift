import Foundation

/// 固定集是开发预置标签，尚未经过用户独立核对；测试不执行任何工具或真实危险动作。
struct NexusIntentRegressionCandidate: Codable, Equatable {
    let id: String
    let source: NexusRecallSource
    let title: String
    let text: String
    let objectPath: String?
    let relevance: Double
    let isConfirmed: Bool
    let aliases: [String]
    let evidencePointers: [String]

    var candidate: NexusRecallCandidate {
        .init(id: id, source: source, title: title, text: text, objectPath: objectPath,
              provenance: "预置开发标签，待用户独立核对", isConfirmed: isConfirmed,
              relevance: relevance, aliases: aliases, evidencePointers: evidencePointers)
    }
}

struct NexusIntentRegressionFixture: Codable, Equatable {
    let id: String
    let goal: String
    let context: String
    let candidates: [NexusIntentRegressionCandidate]
    let expectedObjectID: String?
    let expectedTool: String?
    let shouldClarify: Bool
    let expectedRisk: String
    let availableTools: [String]?
}

struct NexusIntentRegressionObservation: Codable, Equatable, Identifiable {
    let id: String
    let goal: String
    let expectedObjectID: String?
    let actualObjectID: String?
    let expectedTool: String?
    let actualTool: String?
    let expectedClarification: Bool
    let actualClarification: Bool
    let expectedRisk: String
    let actualRisk: String
    let safetyGatePassed: Bool

    var objectCorrect: Bool { expectedObjectID == actualObjectID }
    var toolCorrect: Bool { expectedTool == actualTool }
    var clarificationCorrect: Bool { expectedClarification == actualClarification }
    var riskCorrect: Bool { expectedRisk == actualRisk }
    var passed: Bool { objectCorrect && toolCorrect && clarificationCorrect && riskCorrect && safetyGatePassed }
    var issues: [String] {
        var result: [String] = []
        if !objectCorrect { result.append("对象：预期 \(expectedObjectID ?? "无")，实际 \(actualObjectID ?? "无")") }
        if !toolCorrect { result.append("工具：预期 \(expectedTool ?? "无")，实际 \(actualTool ?? "无")") }
        if !clarificationCorrect { result.append("澄清：预期 \(expectedClarification)，实际 \(actualClarification)") }
        if !riskCorrect { result.append("风险：预期 \(expectedRisk)，实际 \(actualRisk)") }
        if !safetyGatePassed { result.append("含糊或待澄清任务泄漏了执行权限") }
        return result
    }
}

struct NexusIntentRegressionReport: Codable, Equatable {
    let observations: [NexusIntentRegressionObservation]
    let labelReviewPending: Bool
    let labelStatus: String
    let scoringMethod: String
    var total: Int { observations.count }
    var objectCorrect: Int { observations.filter(\.objectCorrect).count }
    var toolCorrect: Int { observations.filter(\.toolCorrect).count }
    var clarificationCorrect: Int { observations.filter(\.clarificationCorrect).count }
    var riskCorrect: Int { observations.filter(\.riskCorrect).count }
    var exactCorrect: Int { observations.filter(\.passed).count }
    var objectAccuracy: Double { total == 0 ? 0 : Double(objectCorrect) / Double(total) }
    var toolAccuracy: Double { total == 0 ? 0 : Double(toolCorrect) / Double(total) }
    var exactAccuracy: Double { total == 0 ? 0 : Double(exactCorrect) / Double(total) }
    var failures: [NexusIntentRegressionObservation] { observations.filter { !$0.passed } }
}

enum NexusIntentRegressionError: LocalizedError {
    case incorrectCount(Int), duplicateIDs, missingContext(String), invalidRisk(String), invalidExpectedObject(String)
    var errorDescription: String? {
        switch self {
        case .incorrectCount(let count): return "中文固定集必须恰有 50 句，当前是 \(count) 句。"
        case .duplicateIDs: return "固定集包含重复的样本 ID。"
        case .missingContext(let id): return "样本 \(id) 缺少上下文标签。"
        case .invalidRisk(let id): return "样本 \(id) 的风险标签无效。"
        case .invalidExpectedObject(let id): return "样本 \(id) 的预期对象不在候选中，且不是用户原句明确给出的新文件。"
        }
    }
}

enum NexusIntentRegression {
    /// 离线工具清单用于判定目标映射，不表示设备已经拥有发送、付款或 Shell 权限。
    static let fixtureTools: Set<String> = ["workspace_read", "workspace_write", "workspace_delete", "workspace_restore", "workspace_list", "read_file", "write_file", "memory_search", "skill_read", "skill_search", "shell_execute", "shell", "shuyu_execute", "web_lookup", "http_fetch", "calc", "clock", "plan", "verify", "send_message", "purchase"]

    static func load(_ data: Data) throws -> [NexusIntentRegressionFixture] {
        let fixtures = try JSONDecoder().decode([NexusIntentRegressionFixture].self, from: data)
        guard fixtures.count == 50 else { throw NexusIntentRegressionError.incorrectCount(fixtures.count) }
        guard Set(fixtures.map(\.id)).count == fixtures.count else { throw NexusIntentRegressionError.duplicateIDs }
        for fixture in fixtures {
            guard !fixture.id.isEmpty, !fixture.goal.isEmpty, !fixture.context.isEmpty else { throw NexusIntentRegressionError.missingContext(fixture.id) }
            guard NexusIntentRisk(rawValue: fixture.expectedRisk) != nil else { throw NexusIntentRegressionError.invalidRisk(fixture.id) }
            if let id = fixture.expectedObjectID, !fixture.candidates.contains(where: { $0.id == id }), !id.hasPrefix("user-object:") {
                throw NexusIntentRegressionError.invalidExpectedObject(fixture.id)
            }
        }
        return fixtures
    }

    static func evaluate(data: Data, availableTools: Set<String> = fixtureTools) throws -> NexusIntentRegressionReport {
        let fixtures = try load(data)
        let observations = fixtures.map { fixture in
            let card = NexusIntentCompiler.compile(goal: fixture.goal, candidates: fixture.candidates.map(\.candidate),
                availableTools: fixture.availableTools.map { Set($0) } ?? availableTools)
            return NexusIntentRegressionObservation(id: fixture.id, goal: fixture.goal,
                expectedObjectID: fixture.expectedObjectID, actualObjectID: card.objectID,
                expectedTool: fixture.expectedTool, actualTool: card.preferredTool,
                expectedClarification: fixture.shouldClarify, actualClarification: card.clarification != nil,
                expectedRisk: fixture.expectedRisk, actualRisk: card.risk.rawValue,
                safetyGatePassed: (!fixture.shouldClarify || card.allowedTools.isEmpty)
                    && (!card.isAmbiguous || card.allowedTools.isDisjoint(with: NexusIntentCompiler.shellTools)))
        }
        return NexusIntentRegressionReport(observations: observations, labelReviewPending: true,
            labelStatus: "预置开发标签，待用户独立核对；一致率不能证明真实任务智慧。",
            scoringMethod: "本地编译结果逐项对照固定对象、工具、澄清和风险标签；不调用模型评分，不执行工具。")
    }
}
