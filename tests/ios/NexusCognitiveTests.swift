import XCTest
import UIKit
@testable import BlackGod

final class NexusCognitiveReasoningTests: XCTestCase {
    func testInterventionCutsIncomingEdgesWithoutChangingOtherCauses() throws {
        let nodes = [NexusCausalTool.Node(name: "U", bias: 2, parents: [:]), .init(name: "X", bias: 0, parents: ["U": 3]), .init(name: "Y", bias: 1, parents: ["U": 4, "X": 2])]
        XCTAssertEqual(try NexusCausalTool.evaluate(.init(nodes: nodes, interventions: nil))["Y"], 21)
        let changed = try NexusCausalTool.evaluate(.init(nodes: nodes.reversed(), interventions: ["X": 0]))
        XCTAssertEqual(changed["U"], 2); XCTAssertEqual(changed["Y"], 9)
    }
    func testCycleUnknownInterventionAndOverflowAreRejected() {
        let cyclic = [NexusCausalTool.Node(name: "X", bias: 0, parents: ["Y": 1]), .init(name: "Y", bias: 0, parents: ["X": 1])]
        XCTAssertThrowsError(try NexusCausalTool.evaluate(.init(nodes: cyclic, interventions: ["X": 1])))
        XCTAssertThrowsError(try NexusCausalTool.evaluate(.init(nodes: [.init(name: "X", bias: 0, parents: [:])], interventions: ["Z": 1])))
        XCTAssertThrowsError(try NexusCausalTool.evaluate(.init(nodes: [.init(name: "X", bias: .greatestFiniteMagnitude, parents: [:]), .init(name: "Y", bias: 0, parents: ["X": 2])], interventions: nil)))
    }
    func testDependencyCriticalPathAndCycles() throws {
        let result = try NexusDependencyTool.evaluate([.init(id: "finish", duration: 2, dependencies: ["a", "b"]), .init(id: "b", duration: 4, dependencies: []), .init(id: "a", duration: 3, dependencies: [])])
        XCTAssertEqual(result.finish["finish"], 6)
        XCTAssertEqual(result.order.last, "finish")
        XCTAssertThrowsError(try NexusDependencyTool.evaluate([.init(id: "a", duration: 1, dependencies: ["b"]), .init(id: "b", duration: 1, dependencies: ["a"])]))
        XCTAssertThrowsError(try NexusDependencyTool.evaluate([.init(id: "a", duration: -1, dependencies: [])]))
    }
    @MainActor
    func testRealImageTextRecognitionAndBadImageRejection() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 250)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 250))
            ("BLACK GOD 2048" as NSString).draw(at: CGPoint(x: 40, y: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 80), .foregroundColor: UIColor.black])
        }
        let result = try NexusVisualObservation.recognize(XCTUnwrap(image.pngData()))
        XCTAssertTrue(result.text.contains("BLACK GOD"), result.text)
        XCTAssertTrue(result.text.contains("2048"), result.text)
        XCTAssertTrue(result.source.contains("SHA256="))
        XCTAssertThrowsError(try NexusVisualObservation.recognize(Data("invalid".utf8)))
    }
}

@MainActor
final class NexusCognitiveControlTests: XCTestCase {
    private func store() -> NexusCognitiveControl {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return NexusCognitiveControl(url: dir.appendingPathComponent("control.json"))
    }
    func testProposalCannotPromoteItselfAndConflictNeedsExplicitReplacement() throws {
        let store = store()
        try store.propose(topic: "test", statement: "old", source: "original")
        XCTAssertFalse(store.context.contains("old"))
        let first = try XCTUnwrap(store.candidates.first)
        try store.confirm(first.id)
        try store.propose(topic: "other", statement: "retain", source: "source")
        try store.confirm(XCTUnwrap(store.candidates.first).id)
        let retained = try XCTUnwrap(store.active.first { $0.topic == "other" })
        try store.propose(topic: "TEST", statement: "new", source: "correction")
        let replacement = try XCTUnwrap(store.candidates.first)
        XCTAssertThrowsError(try store.confirm(replacement.id))
        try store.confirm(replacement.id, replacing: first.id)
        XCTAssertTrue(store.active.contains(retained)); XCTAssertFalse(store.active.contains(first))
        XCTAssertTrue(store.state.records.contains { $0.id == first.id && $0.withdrawnAt != nil })
        try store.restore(first.id)
        XCTAssertTrue(store.candidates.contains { $0.statement == "old" })
        XCTAssertFalse(store.active.contains { $0.statement == "old" })
    }
    func testExpiredUnknownAndRevokedPermissionsFailWithAudit() throws {
        let store = store()
        let shell = NexusToolCall(id: UUID(), name: "shell_execute", arguments: ["command": "private-input"])
        XCTAssertThrowsError(try store.begin(shell))
        try store.grantWorkspace(now: Date().addingTimeInterval(-1801))
        XCTAssertThrowsError(try store.begin(shell))
        try store.grantWorkspace()
        _ = try store.begin(shell)
        XCTAssertThrowsError(try store.begin(.init(id: UUID(), name: "grant_admin", arguments: [:])))
        try store.revokeAll()
        XCTAssertThrowsError(try store.begin(shell))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(store.state.audit), as: UTF8.self).contains("private-input"))
    }
    func testRevocationDuringExecutionSuppressesResult() async throws {
        let store = store()
        var tools = NexusToolRegistry(control: store)
        tools.register(RevokingTool(control: store))
        let result = await tools.execute(.init(id: UUID(), name: "calc", arguments: [:]))
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.output.contains("stale result"))
        XCTAssertTrue(store.state.audit.contains { $0.event == "permission.revoked" })
    }
    /// 1.2.0 build 7 及以前落盘的治理文件没有 governanceEnabled / selfDecisions 键；升级后必须仍可读写，不能整体停用受管操作。
    func testBuild7GovernanceFileWithoutNewKeysStillLoadsAndStaysWritable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("control.json")
        let legacy = """
        {"version":1,"stopped":false,"records":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","topic":"旧资料","statement":"旧版本写入","source":"user verified","recordedAt":700000000,"confirmedAt":700000001}],"audit":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FE","date":700000001,"event":"knowledge.confirmed","subject":"旧资料"}]}
        """
        try Data(legacy.utf8).write(to: url)
        let control = NexusCognitiveControl(url: url)
        XCTAssertNil(control.error)
        XCTAssertEqual(control.active.count, 1)
        XCTAssertTrue(control.state.governanceEnabled)
        XCTAssertTrue(control.state.selfDecisions.isEmpty)
        try control.grantWorkspace()
        XCTAssertNotNil(control.state.workspaceUntil)
        let reopened = NexusCognitiveControl(url: url)
        XCTAssertNil(reopened.error)
        XCTAssertEqual(reopened.active.count, 1)
    }
    func testRestartRemovesLeaseAndKeepsKnowledge() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("control.json")
        let first = NexusCognitiveControl(url: url)
        try first.propose(topic: "x", statement: "remember", source: "user verified")
        try first.confirm(XCTUnwrap(first.candidates.first).id)
        try first.grantWorkspace()
        let next = NexusCognitiveControl(url: url)
        XCTAssertEqual(next.active.count, 1)
        XCTAssertNil(next.state.workspaceUntil)
        XCTAssertThrowsError(try next.begin(.init(id: UUID(), name: "shell_execute", arguments: [:])))
    }
    func testCorruptAndUnwritableStoresFailClosed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("control.json")
        try Data("broken".utf8).write(to: url)
        let corrupt = NexusCognitiveControl(url: url)
        XCTAssertThrowsError(try corrupt.begin(.init(id: UUID(), name: "calc", arguments: [:])))
        XCTAssertThrowsError(try corrupt.propose(topic: "x", statement: "y", source: "z"))
        XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
        let unwritable = NexusCognitiveControl(url: url.appendingPathComponent("child"))
        XCTAssertThrowsError(try unwritable.begin(.init(id: UUID(), name: "calc", arguments: [:])))
    }
    func testInterruptedAuditIsRecoveredWithoutPretendingNoSideEffects() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("control.json")
        let original = NexusCognitiveControl(url: url)
        let call = NexusToolCall(id: UUID(), name: "calc", arguments: ["expression": "2+2"])
        _ = try original.begin(call)
        let recovered = NexusCognitiveControl(url: url)
        XCTAssertEqual(recovered.state.audit.filter { $0.event == "tool.interrupted" }.count, 1)
        XCTAssertFalse(recovered.state.audit.contains { $0.event == "tool.completed" })
        XCTAssertEqual(NexusCognitiveControl(url: url).state.audit.filter { $0.event == "tool.interrupted" }.count, 1)
    }
    func testFailedKnowledgeWriteCannotChangeActiveRevision() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("control.json")
        let store = NexusCognitiveControl(url: url)
        try store.propose(topic: "first", statement: "keep", source: "test")
        try store.confirm(XCTUnwrap(store.candidates.first).id)
        try store.propose(topic: "second", statement: "new", source: "test")
        let id = try XCTUnwrap(store.candidates.first).id
        let old = store.active
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.confirm(id))
        XCTAssertEqual(store.active, old)
    }
    func testModelProposalHasNoActivationTool() async throws {
        let store = store(); var tools = NexusToolRegistry(control: store)
        tools.register(NexusKnowledgeProposalTool(control: store)); tools.register(NexusCausalTool()); tools.register(NexusDependencyTool())
        XCTAssertEqual(Set(tools.nativeDefinitions.map(\.name)), ["knowledge_propose", "causal_model", "dependency_plan"])
        let result = await tools.execute(.init(id: UUID(), name: "knowledge_propose", arguments: ["topic": "hypothesis", "statement": "unverified", "source": "model inference"]))
        XCTAssertTrue(result.succeeded); XCTAssertEqual(store.candidates.count, 1); XCTAssertTrue(store.active.isEmpty)
        XCTAssertFalse(tools.contains("knowledge_confirm"))
    }
    func testSelfDecisionLifecycleAndRiskGating() throws {
        let store = store()
        let run = UUID()
        store.continuity.begin(run: run, goal: "self improve", redacting: nil)

        let _ = try store.proposeSelfDecision(scope: "计划", issue: "算力消耗", proposal: "新增缓存层", expectedGain: "减少20%重复计算", risk: "low")
        XCTAssertEqual(store.state.selfDecisions.count, 1)
        let created = try XCTUnwrap(store.state.selfDecisions.first)
        XCTAssertEqual(created.run, run)
        XCTAssertEqual(created.status, .proposed)

        XCTAssertThrowsError(try store.reviewSelfDecision(created.id, approved: true, note: ""))
        try store.reviewSelfDecision(created.id, approved: true, note: "风险隔离清晰")
        XCTAssertEqual(store.state.selfDecisions.first?.status, .approved)
        try store.publishSelfDecision(created.id, note: "已通过复审，记录发布")
        XCTAssertEqual(store.state.selfDecisions.first?.status, .published)

        let blocked = try store.proposeSelfDecision(scope: "合规", issue: "跨区域执行", proposal: "全局自学习", expectedGain: "效率提升", risk: "高")
        try store.reviewSelfDecision(blocked, approved: true, note: "风险高")
        XCTAssertThrowsError(try store.publishSelfDecision(blocked, note: "尝试发布"))
        XCTAssertEqual(store.state.selfDecisions.last?.status, .rejected)
    }
    func testAutoSelfDecisionGenerationFromFailedToolTraces() throws {
        let store = store()
        let run = UUID()
        store.continuity.begin(run: run, goal: "auto close", redacting: nil)
        let traces = [
            NexusToolTrace(stepID: UUID(), round: 0,
                           call: NexusToolCall(id: UUID(), name: "calc", arguments: ["expression": "1/0"]),
                           result: "division by zero", succeeded: false, timestamp: Date()),
            NexusToolTrace(stepID: UUID(), round: 0,
                           call: NexusToolCall(id: UUID(), name: "shell_execute", arguments: ["command": "echo"]),
                           result: "permission denied", succeeded: false, timestamp: Date().addingTimeInterval(1)),
            NexusToolTrace(stepID: UUID(), round: 1,
                           call: NexusToolCall(id: UUID(), name: "calc", arguments: ["expression": "2+2"]),
                           result: "4", succeeded: true, timestamp: Date().addingTimeInterval(2))
        ]
        let ids = try store.generateSelfDecisionsFromToolFailures(traces, runID: run.uuidString, maxSuggestions: 3)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(store.state.selfDecisions.count, 2)
        XCTAssertTrue(store.state.selfDecisions.allSatisfy { $0.status == .proposed })
        XCTAssertTrue(store.state.selfDecisions.allSatisfy { $0.scope == "工具可靠性" })
    }
    func testAutoSelfDecisionGenerationIsIdempotentForSameFailures() throws {
        let store = store()
        let run = UUID()
        store.continuity.begin(run: run, goal: "idempotent", redacting: nil)
        let traces = [
            NexusToolTrace(stepID: UUID(), round: 0,
                           call: NexusToolCall(id: UUID(), name: "clock", arguments: ["timezone": "Invalid/Zone"]),
                           result: "unknown timezone", succeeded: false, timestamp: Date())
        ]
        _ = try store.generateSelfDecisionsFromToolFailures(traces, runID: run.uuidString, maxSuggestions: 2)
        let countAfterFirst = store.state.selfDecisions.count
        _ = try store.generateSelfDecisionsFromToolFailures(traces, runID: run.uuidString, maxSuggestions: 2)
        XCTAssertEqual(store.state.selfDecisions.count, countAfterFirst)
    }
    func testAutoSelfDecisionGenerationIgnoresGovernanceAndSuccessfulTools() throws {
        let store = store()
        let run = UUID()
        store.continuity.begin(run: run, goal: "ignore successful tools", redacting: nil)
        let traces = [
            NexusToolTrace(stepID: UUID(), round: 0,
                           call: NexusToolCall(id: UUID(), name: "knowledge_propose", arguments: ["topic": "x"]),
                           result: "ok", succeeded: false, timestamp: Date()),
            NexusToolTrace(stepID: UUID(), round: 1,
                           call: NexusToolCall(id: UUID(), name: "clock", arguments: [:]),
                           result: "2026-09-09 00:00:00", succeeded: true, timestamp: Date().addingTimeInterval(1))
        ]
        let ids = try store.generateSelfDecisionsFromToolFailures(traces, runID: run.uuidString, maxSuggestions: 2)
        XCTAssertEqual(ids.count, 0)
        XCTAssertEqual(store.state.selfDecisions.count, 0)
    }
    func testGovernanceCloseDeniesSelfDecisionToolsAndWritesAudit() throws {
        let store = store()
        try store.setGovernanceEnabled(false)
        let denied = NexusToolCall(id: UUID(), name: "self_decision_proposal", arguments: [
            "scope": "策略",
            "issue": "高成本任务",
            "proposal": "缩短并行链路并加缓存",
            "expected_gain": "提升吞吐",
            "risk": "low"
        ])
        XCTAssertThrowsError(try store.begin(denied))
        XCTAssertTrue(store.state.audit.contains { $0.event == "tool.denied" && $0.subject.contains("governance-closed") })

        XCTAssertNoThrow(try store.begin(.init(id: UUID(), name: "clock", arguments: [:])))
        XCTAssertEqual(store.state.records.count, 0)
    }
}
private struct RevokingTool: NexusTool {
    let name = "calc"
    let control: NexusCognitiveControl
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        try? await control.revokeAll()
        return .init(callID: call.id, output: "stale result", succeeded: true)
    }
}
