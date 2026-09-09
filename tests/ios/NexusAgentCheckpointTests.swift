import XCTest
@testable import BlackGod

private struct CheckpointTestPlanner: NexusPlanning {
    func makePlan(for goal: String) -> NexusTaskPlan {
        NexusTaskPlan(id: UUID(), goal: goal, steps: [NexusTaskStep(title: "执行一次")], createdAt: Date())
    }
}

private struct CheckpointProbeTool: NexusTool {
    let name = "probe"
    let action: () -> Void
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        action()
        return NexusToolResult(callID: call.id, output: "已执行", succeeded: true)
    }
}

@MainActor
final class NexusAgentCheckpointTests: XCTestCase {
    private var folder: URL!
    private var conversation: NexusConversationStore { NexusConversationStore(url: folder.appendingPathComponent("chat.json")) }
    private var store: NexusAgentCheckpointStore { NexusAgentCheckpointStore(url: folder.appendingPathComponent("chat.agent.json")) }
    private var connection: NexusModelEntry { NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel) }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: folder) }

    func testRestartShowsInterruptedTaskWithoutAutomaticallyCallingModel() throws {
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "处理文件", connection: connection)
        saved.pendingTool = "shell_execute"
        try store.save(saved)
        var requests = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in requests += 1; return "不应请求" })
        XCTAssertTrue(vm.canResume)
        XCTAssertEqual(vm.taskCheckpoint?.state, .interrupted)
        XCTAssertEqual(try store.load()?.pendingTool, "shell_execute")
        XCTAssertEqual(requests, 0)
        XCTAssertFalse(vm.isTyping)
    }

    func testResumeCarriesGoalCriteriaEvidenceAndDoesNotDuplicateUserMessage() async throws {
        try conversation.save([ChatMessage(role: "user", content: "计算总价")])
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "计算总价", connection: connection)
        saved.criteria = ["不能漏掉运费"]
        saved.evidence = [NexusSavedEvidence(callID: UUID(), stepID: UUID(), tool: "calc", output: "36", succeeded: true)]
        saved.pendingTool = "shell_execute"
        try store.save(saved)
        var requests: [String] = []
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { messages, _ in
            requests.append(messages.map(\.content).joined(separator: "\n"))
            return #"{"answer":"已有商品总价36，请补充运费。"}"#
        })
        vm.resume()
        try await finish(vm)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].contains("不能漏掉运费"))
        XCTAssertTrue(requests[0].contains("结果=36"))
        XCTAssertTrue(requests[0].contains("待确认工具：shell_execute"))
        XCTAssertTrue(requests[0].contains("不得直接重放旧脚本"))
        XCTAssertEqual(vm.messages.filter { $0.role == "user" }.count, 1)
        XCTAssertFalse(vm.canResume)
        XCTAssertEqual(try store.load()?.state, .answered)
    }

    func testChangedDestinationCannotReceiveRecoveryData() throws {
        var other = connection
        other.connectionID = "different-account"
        try store.save(NexusAgentCheckpoint(id: UUID(), goal: "私人任务", connection: other))
        var requests = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in requests += 1; return "不应请求" })
        vm.resume()
        XCTAssertFalse(vm.isTyping)
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(vm.lastError?.contains("原来的连接") == true)
        XCTAssertTrue(vm.canResume)
    }

    func testFinalAnswerIsRecoveredExactlyOnceAfterPartialCommit() throws {
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "测试", connection: connection)
        saved.state = .answered
        saved.finalMessage = ChatMessage(role: "assistant", content: "已经生成的答复")
        try store.save(saved)
        let first = ChatViewModel(store: conversation)
        let second = ChatViewModel(store: conversation)
        XCTAssertEqual(first.messages.count, 1)
        XCTAssertEqual(second.messages.count, 1)
        XCTAssertEqual(second.messages.first?.id, saved.finalMessage?.id)
        XCTAssertFalse(second.canResume)
    }

    func testDiscardPersistsAcrossRestart() throws {
        try store.save(NexusAgentCheckpoint(id: UUID(), goal: "停止的任务", connection: connection))
        let vm = ChatViewModel(store: conversation)
        vm.discardRecovery()
        XCTAssertFalse(ChatViewModel(store: conversation).canResume)
        XCTAssertEqual(try store.load()?.state, .discarded)
    }

    func testCorruptCheckpointIsReportedAndNeverReplayed() throws {
        try Data("{broken".utf8).write(to: store.url)
        let vm = ChatViewModel(store: conversation)
        XCTAssertFalse(vm.canResume)
        XCTAssertTrue(vm.lastError?.contains("读取任务进度失败") == true)
        XCTAssertEqual(try Data(contentsOf: store.url), Data("{broken".utf8))
    }

    func testSecretRedactionAndEvidenceBoundsDoNotRetainToolArguments() throws {
        let key = "secret-fixture-unique"
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "任务 " + key, connection: connection)
        let plan = CheckpointTestPlanner().makePlan(for: "任务")
        let traces = (0..<40).map { _ in NexusToolTrace(stepID: plan.steps[0].id, round: 0,
            call: NexusToolCall(id: UUID(), name: "shell_execute", arguments: ["script": "DO_NOT_STORE_THIS_ARGUMENT"]),
            result: key + String(repeating: "数据", count: 5000) + "最终结果", succeeded: true, timestamp: Date()) }
        saved.update(NexusAgentProgress(plan: plan, criteria: ["条件"], traces: traces, pendingTool: nil))
        try store.save(saved, redacting: key)
        let loaded = try XCTUnwrap(store.load())
        let raw = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertFalse(raw.contains(key))
        XCTAssertFalse(raw.contains("DO_NOT_STORE_THIS_ARGUMENT"))
        XCTAssertEqual(loaded.evidence.count, 24)
        XCTAssertTrue(loaded.evidence.last?.output.hasSuffix("最终结果") == true)
        XCTAssertLessThan(raw.utf8.count, 150_000)
    }

    func testFailedCheckpointPreventsTextToolSideEffect() async {
        var executions = 0
        var tools = NexusToolRegistry()
        tools.register(CheckpointProbeTool { executions += 1 })
        let executor = NexusExecutor(planner: CheckpointTestPlanner(), verifier: NexusContentVerifier(),
            model: { _ in #"{"name":"probe","arguments":{}}"# }, tools: tools,
            onCheckpoint: { _, _, pending in if pending != nil { throw URLError(.cannotWriteToFile) } })
        _ = await executor.run(goal: "执行")
        XCTAssertEqual(executions, 0)
        XCTAssertTrue(executor.lastError?.contains("保存任务进度失败") == true)
    }

    func testPendingMarkerPrecedesNativeToolAndResultIsPersisted() async throws {
        var markers: [String?] = []
        var calls = 0
        var tools = NexusToolRegistry()
        tools.register(NexusCalculatorTool())
        let executor = NexusExecutor(planner: CheckpointTestPlanner(), verifier: NexusContentVerifier(), tools: tools,
            nativeTurn: { messages, _ in
                calls += 1
                if calls == 1 {
                    return try NexusNativeCodec.decode(Data(#"{"choices":[{"message":{"tool_calls":[{"id":"call_1","type":"function","function":{"name":"calc","arguments":"{\"expression\":\"3+4\"}"}}]},"finish_reason":"tool_calls"}]}"#.utf8), type: .openAICompatible)
                }
                XCTAssertTrue(markers.contains { $0 == "calc" })
                XCTAssertNil(markers.last!)
                guard case .results(let results) = messages.last else { throw NexusError.invalidResponse }
                XCTAssertEqual(results.first?.1.output, "7")
                return try NexusNativeCodec.decode(Data(#"{"choices":[{"message":{"content":"7"},"finish_reason":"stop"}]}"#.utf8), type: .openAICompatible)
            }, onCheckpoint: { plan, traces, pending in
                markers.append(pending)
                var saved = NexusAgentCheckpoint(id: UUID(), goal: "计算", connection: self.connection)
                saved.update(NexusAgentProgress(plan: plan, criteria: [], traces: traces, pendingTool: pending))
                try self.store.save(saved)
            })
        let answer = await executor.run(goal: "计算")
        XCTAssertEqual(answer, "7")
        XCTAssertEqual(try store.load()?.evidence.last?.output, "7")
        XCTAssertNil(try store.load()?.pendingTool)
    }

    func testCannotStartIfCheckpointPathIsUnwritable() throws {
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: true)
        var requests = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in requests += 1; return "未执行" })
        vm.send("新任务")
        XCTAssertFalse(vm.isTyping)
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertTrue(vm.lastError?.contains("任务尚未开始") == true)
    }


    func testPostToolWriteFailureLeavesUnknownOutcomeForRecovery() async throws {
        var tools = NexusToolRegistry()
        tools.register(NexusCalculatorTool())
        let executor = NexusExecutor(planner: CheckpointTestPlanner(), verifier: NexusContentVerifier(),
            model: { _ in #"{"name":"calc","arguments":{"expression":"3+4"}}"# }, tools: tools,
            onCheckpoint: { plan, traces, pending in
                if !traces.isEmpty { throw URLError(.cannotWriteToFile) }
                var saved = NexusAgentCheckpoint(id: UUID(), goal: "计算", connection: self.connection)
                saved.update(NexusAgentProgress(plan: plan, criteria: [], traces: traces, pendingTool: pending))
                try self.store.save(saved)
            })
        _ = await executor.run(goal: "计算")
        XCTAssertEqual(executor.toolTraces.first?.result, "7")
        XCTAssertNotNil(executor.lastError)
        XCTAssertEqual(try store.load()?.pendingTool, "calc")
        XCTAssertTrue(try store.load()?.evidence.isEmpty == true)
    }

    func testWarningAnswerRetainsRecoveryAndRestoresWithoutDuplicate() async throws {
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, nativeCompletion: { _, _, _ in
            try NexusNativeCodec.decode(Data(#"{"choices":[{"message":{"content":"未确认的答复"},"finish_reason":"stop"}]}"#.utf8), type: .openAICompatible)
        }, completion: { messages, _ in
            let prompt = messages.last?.content ?? ""
            if prompt.contains("[任务规划]") { return #"{"steps":["检查目标"]}"# }
            if prompt.contains("[结果复核]") { return "不是合法复核JSON" }
            return "未确认的答复"
        })
        vm.send("检查目标")
        try await finish(vm)
        XCTAssertTrue(vm.canResume)
        XCTAssertEqual(vm.taskCheckpoint?.state, .failed)
        let restored = ChatViewModel(store: conversation)
        XCTAssertTrue(restored.canResume)
        XCTAssertEqual(restored.messages.filter { $0.role == "assistant" }.count, 1)
        XCTAssertTrue(restored.taskCheckpoint?.recoveryContext.contains("未取得有效的模型复核结果") == true)
    }

    func testUnsupportedVersionFailsWithoutDiscardingRecord() throws {
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "新版本任务", connection: connection)
        saved.version = 2
        try store.save(saved)
        XCTAssertThrowsError(try store.load())
        let vm = ChatViewModel(store: conversation)
        XCTAssertFalse(vm.canResume)
        XCTAssertNotNil(vm.lastError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
    }

    private func finish(_ vm: ChatViewModel) async throws {
        for _ in 0..<200 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(vm.isTyping)
    }
}
