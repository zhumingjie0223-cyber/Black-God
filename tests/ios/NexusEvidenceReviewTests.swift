import XCTest
@testable import BlackGod

private struct EvidencePlan: NexusPlanning {
    var count = 1
    func makePlan(for goal: String) -> NexusTaskPlan {
        NexusTaskPlan(id: UUID(), goal: goal,
            steps: (0..<count).map { NexusTaskStep(title: "检查\($0)") }, createdAt: Date())
    }
}

private struct EvidenceProbe: NexusTool {
    let name: String
    let action: () -> Void
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        action()
        return NexusToolResult(callID: call.id, output: "观察结果", succeeded: true)
    }
}

private struct EvidenceComposite: NexusAuthorizableTool {
    let name = "composite"
    let children: NexusToolRegistry
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        await execute(call, authorize: nil, onTrace: nil)
    }
    func execute(_ call: NexusToolCall, authorize: NexusToolAuthorization?,
                 onTrace: NexusNestedTraceObserver?) async -> NexusToolResult {
        let inner = NexusToolCall(id: UUID(), name: "probe", arguments: [:])
        let result = await children.execute(inner, authorize: authorize, onTrace: onTrace)
        await onTrace?(NexusToolTrace(stepID: call.id, round: 0, call: inner, result: result.output,
            succeeded: result.succeeded, timestamp: Date(), authorizationDenied: result.output.hasPrefix("授权拦截：")))
        return NexusToolResult(callID: call.id, output: result.output, succeeded: result.succeeded)
    }
}

@MainActor
final class NexusEvidenceReviewTests: XCTestCase {
    private func record(_ tool: String, output: String = "观察结果", succeeded: Bool = true,
                        denied: Bool = false, scope: String? = nil) -> NexusEvidenceRecord {
        NexusEvidenceRecord(id: NexusEvidenceAudit.toolID(UUID()), stepID: UUID(), tool: tool,
            succeeded: succeeded, output: output, authorizationDenied: denied, scope: scope)
    }

    func testThreeChecksCannotBeOverriddenByACompletionStatement() async {
        let audit = NexusEvidenceAudit.review(missingSlots: ["对象"], answer: "文件已删除。",
            records: [record("workspace_delete", succeeded: false, denied: true)],
            requirements: [NexusEvidenceRequirement(id: "delete", description: "删除指定文件", toolName: "workspace_delete")],
            referencedEvidenceIDs: ["file:missing"], allowedTools: ["workspace_read"])
        XCTAssertFalse(audit.slotsComplete)
        XCTAssertFalse(audit.evidenceConsistent)
        XCTAssertFalse(audit.authorized)
        XCTAssertFalse(audit.passed)
    }

    func testUnrelatedSuccessfulCalculationCannotProveDeletion() async {
        let audit = NexusEvidenceAudit.review(answer: "36，报告已删除。", records: [record("calc", output: "36")])
        XCTAssertFalse(audit.passed)
        XCTAssertTrue(audit.issues.contains { $0.contains("对应操作工具") })
    }

    func testFailedFileACannotBeHiddenBySuccessfulFileB() async {
        let audit = NexusEvidenceAudit.review(answer: "B已写入，A仍失败。", records: [
            record("workspace_write", succeeded: false, scope: "path=A"),
            record("workspace_write", scope: "path=B")])
        XCTAssertFalse(audit.passed)
    }

    func testCalculatorMatchesNumericTokensAndRejectsContradictions() async {
        let value = record("calc", output: "36.0")
        let requirement = NexusEvidenceRequirement(id: "price", description: "算出总价", toolName: "calc", expectedOutput: "36")
        for answer in ["总价36元", "结果36.0", "12乘3等于36"] {
            XCTAssertTrue(NexusEvidenceAudit.review(answer: answer, records: [value], requirements: [requirement]).passed, answer)
        }
        for answer in ["总价360元", "结果3.6", "不是36而是35"] {
            XCTAssertFalse(NexusEvidenceAudit.review(answer: answer, records: [value], requirements: [requirement]).passed, answer)
        }
    }

    func testNegatedCompletionDoesNotPretendToExecute() async {
        XCTAssertTrue(NexusEvidenceAudit.review(answer: "没有证据证明已删除，请先核对对象。", records: []).passed)
        XCTAssertFalse(NexusEvidenceAudit.review(answer: "此前未处理其他事项，现在已删除报告。", records: []).passed)
    }

    func testWebSourceIsEvidenceAndCannotBecomeAVerifiedFact() async {
        let source = NexusEvidenceReference(id: "url:https://example.org", kind: .web, label: "示例页面")
        let requirement = NexusEvidenceRequirement(id: "source", description: "来源已核对", evidenceIDs: [source.id],
            requiresSuccessfulTool: false, requiresVerifiedSource: true)
        XCTAssertFalse(NexusEvidenceAudit.review(answer: "页面声称如此。", records: [], references: [source], requirements: [requirement]).passed)
        XCTAssertEqual(NexusEvidence.sourceReferences(in: #"{"sourceID":"url:https://example.org","verified":true}"#).first?.verified, false)
    }

    func testLegacyStepAndEvidenceDecodeWithoutNewFields() async throws {
        let stepID = UUID()
        let oldStep = #"{"id":"\#(stepID)","title":"旧步骤","status":"passed","result":"旧内容"}"#
        let step = try JSONDecoder().decode(NexusTaskStep.self, from: Data(oldStep.utf8))
        XCTAssertEqual(step.id, stepID)
        XCTAssertTrue(step.evidenceIDs.isEmpty)
        XCTAssertNil(step.executionVerified)
        let oldEvidence = #"{"callID":"\#(UUID())","stepID":"\#(stepID)","tool":"calc","output":"36","succeeded":true}"#
        let evidence = try JSONDecoder().decode(NexusSavedEvidence.self, from: Data(oldEvidence.utf8))
        XCTAssertNil(evidence.authorizationDenied)
        XCTAssertTrue(evidence.evidenceID.hasPrefix("tool:"))
    }

    func testNativeAndTextRequestsUseTheSameAuthorizationGate() async throws {
        for native in [false, true] {
            var executions = 0
            var tools = NexusToolRegistry()
            tools.register(EvidenceProbe(name: "calc") { executions += 1 })
            var turns = 0
            let text: NexusExecutor.ModelCall = { _ in
                turns += 1
                return turns == 1 ? #"{"name":"calc","arguments":{"expression":"1+1"}}"# : "工具被拒绝，未执行。"
            }
            let turn: NexusNativeTurn = { _, _ in
                turns += 1
                return NexusNativeReply(text: turns == 1 ? #"{"name":"calc","arguments":{"expression":"1+1"}}"# : "工具被拒绝，未执行。",
                    calls: [], assistant: ["role": "assistant", "content": ""])
            }
            let executor = NexusExecutor(planner: EvidencePlan(), verifier: NexusContentVerifier(), model: text,
                tools: tools, nativeTurn: native ? turn : nil, authorizeTool: { _ in "当前对象不允许该操作。" })
            _ = await executor.run(goal: "检查对象")
            XCTAssertEqual(executions, 0)
            XCTAssertEqual(executor.toolTraces.count, 1)
            XCTAssertTrue(executor.toolTraces[0].authorizationDenied)
            XCTAssertFalse(executor.toolTraces[0].succeeded)
            XCTAssertEqual(executor.plan?.steps[0].evidenceIDs, [NexusEvidenceAudit.toolID(executor.toolTraces[0].call.id)])
            XCTAssertEqual(executor.plan?.steps[0].status, .failed)
        }
    }

    func testCompositeChildAuthorizationAndEvidenceReachExecutor() async {
        var executions = 0
        var children = NexusToolRegistry()
        children.register(EvidenceProbe(name: "probe") { executions += 1 })
        var tools = NexusToolRegistry()
        tools.register(EvidenceComposite(children: children))
        var turns = 0
        let executor = NexusExecutor(planner: EvidencePlan(), verifier: NexusContentVerifier(), model: { _ in
            turns += 1
            return turns == 1 ? #"{"name":"composite","arguments":{}}"# : "子工具被拒绝，未执行。"
        }, tools: tools, authorizeTool: { $0.name == "probe" ? "子工具未授权。" : nil })
        _ = await executor.run(goal: "检查对象")
        XCTAssertEqual(executions, 0)
        XCTAssertEqual(executor.toolTraces.map(\.call.name), ["probe", "composite"])
        XCTAssertTrue(executor.toolTraces.allSatisfy(\.authorizationDenied))
        XCTAssertEqual(Set(executor.plan?.steps[0].evidenceIDs ?? []), Set(executor.toolTraces.map { NexusEvidenceAudit.toolID($0.call.id) }))
    }

    func testContentOnlyStepIsAnsweredAndRepairKeepsFourSlotsAndOriginalPointers() async {
        let source = NexusEvidenceReference(id: "memory:confirmed", kind: .memory, label: "上次报告", verified: true)
        var calls = 0
        let executor = NexusExecutor(planner: EvidencePlan(count: 4), verifier: NexusContentVerifier(), model: { _ in
            calls += 1
            return "结果\(calls)"
        }, sourceEvidence: [source])
        _ = await executor.run(goal: "整理报告")
        let original = executor.plan!.steps.map(\.id)
        XCTAssertTrue(executor.plan!.steps.allSatisfy { $0.status == .answered && $0.executionVerified == false })
        _ = await executor.repair(goal: "整理报告", issues: ["补充遗漏"], answer: "结果", criteria: [])
        XCTAssertEqual(executor.plan!.steps.map(\.id), original)
        XCTAssertEqual(executor.plan!.steps.count, 4)
        XCTAssertTrue(executor.plan!.steps.last!.evidenceIDs.contains(source.id))
        let after = calls
        let second = await executor.repair(goal: "整理报告", issues: ["再修一次"], answer: "结果", criteria: [])
        XCTAssertEqual(second, "")
        XCTAssertEqual(calls, after)
    }
}
