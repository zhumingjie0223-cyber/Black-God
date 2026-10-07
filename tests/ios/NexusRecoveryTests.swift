import Foundation
import XCTest
@testable import BlackGod

private actor RecoveryExecutions {
    private(set) var calls: [NexusToolCall] = []
    func record(_ call: NexusToolCall) { calls.append(call) }
}

private struct RecoveryObservedTool: NexusTool {
    let name: String
    let executions: RecoveryExecutions
    var output = "当前文件内容：预算36。"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        await executions.record(call)
        return .init(callID: call.id, output: output, succeeded: true)
    }
}

@MainActor
final class NexusRecoveryTests: XCTestCase {
    private let path = "reports/phnom-penh.md"
    private var candidate: NexusRecallCandidate {
        .init(id: "file:report", source: .workspaceFile, title: "金边报告", text: "工作区文件名",
              objectPath: path, provenance: "工作区目录")
    }
    private var connection: NexusModelEntry { NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel) }

    private func saved(goal: String, available: Set<String>, pending: String? = nil) -> NexusAgentCheckpoint {
        var saved = NexusAgentCheckpoint(id: UUID(), goal: goal, connection: connection)
        saved.intentCard = NexusIntentCompiler.compile(goal: goal, candidates: [candidate], availableTools: available)
        saved.pendingTool = pending
        saved.state = .interrupted
        return saved
    }

    func testRecoveryWhiteListRejectsAllSideEffectsAndUnknownTools() {
        let policy = NexusRecoveryPolicy(checkpoint: saved(goal: "读取金边报告", available: ["workspace_read"]))
        for name in ["workspace_write", "write_file", "workspace_delete", "workspace_restore", "send_message",
                     "send_email", "payment", "purchase", "shell", "shell_execute", "shuyu_execute", "http_fetch",
                     "knowledge_propose", "self_decision_publish", "unexpected_future_tool"] {
            XCTAssertNotNil(policy.denialReason(for: .init(id: UUID(), name: name, arguments: [:])), name)
        }
        for name in NexusRecoveryPolicy.readOnlyTools {
            XCTAssertNil(policy.denialReason(for: .init(id: UUID(), name: name, arguments: [:])), name)
        }
    }

    func testInheritedPolicyKeepsOriginalOperationAndPathAfterInspectionReplacesCard() throws {
        let available: Set<String> = ["workspace_delete", "workspace_read"]
        let original = saved(goal: "删除金边报告", available: available, pending: "workspace_delete")
        let policy = NexusRecoveryPolicy(checkpoint: original)
        let inspected = try XCTUnwrap(policy.inspectionCard(for: try XCTUnwrap(original.intentCard), availableTools: available))
        XCTAssertEqual(inspected.operation, .inspect)
        var second = NexusAgentCheckpoint(id: UUID(), goal: original.goal, connection: connection)
        second.recoveryPolicy = policy
        second.intentCard = inspected
        let inherited = NexusRecoveryPolicy(checkpoint: second)
        XCTAssertEqual(inherited.protectedOperation, .delete)
        XCTAssertEqual(inherited.objectPath, path)
        XCTAssertEqual(inherited, policy)
    }

    func testDangerousFileRecoveryReadsExactObjectWithoutReplayingDeletion() async throws {
        let executions = RecoveryExecutions()
        var tools = NexusToolRegistry()
        tools.register(RecoveryObservedTool(name: "workspace_read", executions: executions))
        tools.register(RecoveryObservedTool(name: "workspace_delete", executions: executions))
        let checkpoint = saved(goal: "删除金边报告", available: ["workspace_delete", "workspace_read"], pending: "workspace_delete")
        var executionRequests = 0
        let engine = NexusReasoningEngine(tools: tools, model: { prompt in
            if prompt.contains("[任务规划]") {
                XCTAssertTrue(prompt.contains("只读取，不执行原操作"))
                return #"{"steps":["读取指定对象核对现状"]}"#
            }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            return executionRequests == 1 ? #"{"name":"workspace_read","arguments":{"path":"reports/phnom-penh.md"}}"# :
                "当前文件内容预算36，依据本次读取结果；未重复原操作。"
        }, recall: { _ in [self.candidate] }, recoveryPolicy: NexusRecoveryPolicy(checkpoint: checkpoint))
        let outcome = try await engine.run(goal: checkpoint.goal)
        let calls = await executions.calls
        XCTAssertEqual(calls.map(\.name), ["workspace_read"])
        XCTAssertEqual(calls.first?.arguments["path"], path)
        XCTAssertEqual(engine.intentCard?.operation, .inspect)
        XCTAssertEqual(engine.recoveryPolicy?.protectedOperation, .delete)
        XCTAssertTrue(outcome.reviewPassed)
        XCTAssertTrue(outcome.text.contains("原操作未重放"))
        XCTAssertFalse(outcome.requiresClarification)
    }

    func testCompletedActionEvidenceDoesNotMakeCurrentInspectionSkipTools() async throws {
        let executions = RecoveryExecutions()
        var tools = NexusToolRegistry()
        tools.register(RecoveryObservedTool(name: "workspace_read", executions: executions))
        tools.register(RecoveryObservedTool(name: "workspace_delete", executions: executions))
        var checkpoint = saved(goal: "删除金边报告", available: ["workspace_delete", "workspace_read"])
        checkpoint.evidence = [.init(callID: UUID(), stepID: UUID(), tool: "workspace_delete", output: "已删除", succeeded: true)]
        var executionRequests = 0
        let engine = NexusReasoningEngine(tools: tools, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"answer":"历史删除已完成"}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            return executionRequests == 1 ? #"{"name":"workspace_read","arguments":{"path":"reports/phnom-penh.md"}}"# :
                "当前文件仍可读取，依据本次读取结果。"
        }, recall: { _ in [self.candidate] }, recoveryPolicy: NexusRecoveryPolicy(checkpoint: checkpoint))
        let outcome = try await engine.run(goal: checkpoint.goal)
        let calls = await executions.calls
        XCTAssertEqual(calls.map(\.name), ["workspace_read"])
        XCTAssertTrue(outcome.reviewPassed)
        XCTAssertFalse(outcome.text.contains("历史删除已完成"))
    }

    func testRepeatedUnauthorizedDeletionFailsClosedAtToolRoundLimit() async throws {
        let executions = RecoveryExecutions()
        var tools = NexusToolRegistry()
        tools.register(RecoveryObservedTool(name: "workspace_read", executions: executions))
        tools.register(RecoveryObservedTool(name: "workspace_delete", executions: executions))
        let checkpoint = saved(goal: "删除金边报告", available: ["workspace_delete", "workspace_read"])
        let engine = NexusReasoningEngine(tools: tools, maxCalls: 6, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["重做旧任务"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            return #"{"name":"workspace_delete","arguments":{"path":"reports/phnom-penh.md","confirm":"确认删除"}}"#
        }, recall: { _ in [self.candidate] }, recoveryPolicy: NexusRecoveryPolicy(checkpoint: checkpoint))
        do {
            _ = try await engine.run(goal: checkpoint.goal)
            XCTFail("持续越权工具请求必须在轮次上限停止")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("工具轮次上限"))
        }
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(engine.executor?.toolTraces.contains(where: \.authorizationDenied) == true)
        XCTAssertFalse(engine.intentCard?.allowedTools.contains("workspace_delete") ?? true)
    }

    func testNativeModelCannotReplaySuccessfulWriteOrAdvertiseIt() async throws {
        let executions = RecoveryExecutions()
        var tools = NexusToolRegistry()
        tools.register(RecoveryObservedTool(name: "workspace_read", executions: executions))
        tools.register(RecoveryObservedTool(name: "workspace_write", executions: executions))
        var checkpoint = saved(goal: "写入金边报告", available: ["workspace_write", "workspace_read"])
        checkpoint.evidence = [.init(callID: UUID(), stepID: UUID(), tool: "workspace_write",
            output: "已写入，备份ID=" + UUID().uuidString, succeeded: true)]
        var rounds = 0
        let engine = NexusReasoningEngine(tools: tools, maxCalls: 6, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["核对现状"]}"# }
            return #"{"passed":false,"issues":["未取得当前读取证据"]}"#
        }, recall: { _ in [self.candidate] }, recoveryPolicy: NexusRecoveryPolicy(checkpoint: checkpoint), nativeTurn: { _, definitions in
            rounds += 1
            XCTAssertFalse(definitions.contains { $0.name == "workspace_write" })
            let reply = rounds == 1 ? #"{"choices":[{"message":{"tool_calls":[{"id":"old_write","type":"function","function":{"name":"workspace_write","arguments":"{\"path\":\"reports/phnom-penh.md\",\"content\":\"重复写入\"}"}}]},"finish_reason":"tool_calls"}]}"# :
                #"{"choices":[{"message":{"content":"重复写入已被拦截；尚未核对现状。"},"finish_reason":"stop"}]}"#
            return try NexusNativeCodec.decode(Data(reply.utf8), type: .openAICompatible)
        })
        let outcome = try await engine.run(goal: checkpoint.goal)
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(outcome.reviewPassed)
        XCTAssertTrue(engine.executor?.toolTraces.contains(where: \.authorizationDenied) == true)
    }

    func testCommandRecoveryStopsBeforeModelAndIsNotAContinuationQuestion() async throws {
        let executions = RecoveryExecutions()
        var tools = NexusToolRegistry()
        tools.register(RecoveryObservedTool(name: "shell_execute", executions: executions))
        let checkpoint = saved(goal: "执行命令：pwd", available: ["shell_execute"], pending: "shell_execute")
        XCTAssertEqual(checkpoint.intentCard?.operation, .execute)
        let engine = NexusReasoningEngine(tools: tools, model: { _ in
            XCTFail("不能把旧命令再次交给模型执行")
            return "不应执行"
        }, intentModel: { _ in
            XCTFail("恢复门槛必须在分类请求前生效")
            return "不应分类"
        }, recoveryPolicy: NexusRecoveryPolicy(checkpoint: checkpoint))
        let outcome = try await engine.run(goal: checkpoint.goal)
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(engine.modelCalls, 0)
        XCTAssertNil(engine.executor)
        XCTAssertFalse(outcome.requiresClarification)
        XCTAssertFalse(outcome.reviewPassed)
        XCTAssertTrue(outcome.text.contains("完整操作指令"))
    }

    func testSendAndPurchaseRecoveryRequireFreshConcreteInstruction() async throws {
        for goal in ["发送金边报告给小王", "购买金边报告，金额20元"] {
            let checkpoint = saved(goal: goal, available: ["send_message", "purchase"])
            XCTAssertTrue([.send, .purchase].contains(checkpoint.intentCard?.operation))
            let engine = NexusReasoningEngine(tools: NexusToolRegistry(), model: { _ in
                XCTFail("发送和付款不能自动重放")
                return "不应执行"
            }, recoveryPolicy: NexusRecoveryPolicy(checkpoint: checkpoint))
            let outcome = try await engine.run(goal: checkpoint.goal)
            XCTAssertEqual(engine.modelCalls, 0)
            XCTAssertFalse(outcome.requiresClarification)
            XCTAssertTrue(outcome.text.contains("没有再次执行"))
        }
    }

    func testUnexecutedCalculationCanContinueDuringRecovery() async throws {
        var tools = NexusToolRegistry()
        tools.register(NexusCalculatorTool())
        let checkpoint = saved(goal: "计算2+2", available: ["calc"])
        var executionRequests = 0
        let engine = NexusReasoningEngine(tools: tools, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["计算"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            return executionRequests == 1 ? #"{"name":"calc","arguments":{"expression":"2+2"}}"# : "2+2=4"
        }, recoveryPolicy: NexusRecoveryPolicy(checkpoint: checkpoint))
        let outcome = try await engine.run(goal: checkpoint.goal)
        XCTAssertEqual(engine.intentCard?.operation, .calculate)
        XCTAssertTrue(outcome.reviewPassed)
        XCTAssertEqual(engine.executor?.toolTraces.map { $0.call.name }, ["calc"])
    }

    func testOldCheckpointWithoutCardGetsProgramGateFromFreshCompilation() async throws {
        var checkpoint = NexusAgentCheckpoint(id: UUID(), goal: "执行命令：pwd", connection: connection)
        checkpoint.pendingTool = "shell_execute"
        let executions = RecoveryExecutions()
        var tools = NexusToolRegistry()
        tools.register(RecoveryObservedTool(name: "shell_execute", executions: executions))
        let engine = NexusReasoningEngine(tools: tools, model: { _ in
            XCTFail("旧记录没有任务卡也不能免除恢复门槛")
            return "不应执行"
        }, recoveryPolicy: NexusRecoveryPolicy(checkpoint: checkpoint))
        let outcome = try await engine.run(goal: checkpoint.goal)
        XCTAssertEqual(engine.recoveryPolicy?.protectedOperation, .execute)
        XCTAssertFalse(outcome.requiresClarification)
        XCTAssertEqual(engine.modelCalls, 0)
    }

    func testProgressAndStorePreservePolicyAcrossSecondInterruption() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let available: Set<String> = ["workspace_delete", "workspace_read"]
        let original = saved(goal: "删除金边报告", available: available)
        let policy = NexusRecoveryPolicy(checkpoint: original)
        let inspected = try XCTUnwrap(policy.inspectionCard(for: try XCTUnwrap(original.intentCard), availableTools: available))
        var second = NexusAgentCheckpoint(id: UUID(), goal: original.goal, connection: connection)
        second.update(NexusAgentProgress(plan: .init(id: UUID(), goal: inspected.resolvedGoal,
            steps: [NexusTaskStep(title: "核对现状")], createdAt: Date()), criteria: inspected.successCriteria,
            traces: [], pendingTool: "workspace_read", intentCard: inspected, recoveryPolicy: policy))
        second.state = .interrupted
        let store = NexusAgentCheckpointStore(url: folder.appendingPathComponent("recovery.agent.json"))
        try store.save(second)
        let reloaded = try XCTUnwrap(store.load())
        XCTAssertEqual(reloaded.intentCard?.operation, .inspect)
        XCTAssertEqual(reloaded.recoveryPolicy?.protectedOperation, .delete)
        XCTAssertEqual(reloaded.recoveryPolicy?.objectPath, path)
        XCTAssertNotNil(reloaded.recoveryPolicy?.denialReason(for: .init(id: UUID(), name: "workspace_delete", arguments: ["path": path])))
    }

    func testLegacyCheckpointDecodesWithoutRecoveryPolicy() throws {
        let original = saved(goal: "读取金边报告", available: ["workspace_read"])
        let data = try JSONEncoder().encode(original)
        let reloaded = try JSONDecoder().decode(NexusAgentCheckpoint.self, from: data)
        XCTAssertNil(reloaded.recoveryPolicy)
        XCTAssertEqual(reloaded.goal, original.goal)
    }
}
