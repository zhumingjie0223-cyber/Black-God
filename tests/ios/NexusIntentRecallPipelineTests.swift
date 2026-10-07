import Foundation
import XCTest
@testable import BlackGod

private actor RecallPipelineCalls {
    var calls: [NexusToolCall] = []
    func append(_ call: NexusToolCall) { calls.append(call) }
}

private struct RecallPipelineReader: NexusTool {
    let name = "workspace_read"
    let usage = "读取回归用临时工作区的真实文件"
    let root: URL
    let calls: RecallPipelineCalls

    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        await calls.append(call)
        guard let path = NexusRecallCandidate.workspaceRelativePath(call.arguments["path"]) else {
            return .init(callID: call.id, output: "无效文件路径", succeeded: false)
        }
        do {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            return .init(callID: call.id, output: String(decoding: data, as: UTF8.self), succeeded: true)
        } catch {
            return .init(callID: call.id, output: error.localizedDescription, succeeded: false)
        }
    }
}

/// 以真实文件、会话和记忆走召回入口；预期对象不依赖手写的相关性分数。
@MainActor
final class NexusIntentRecallPipelineTests: XCTestCase {
    private var folder: URL!
    private let available: Set<String> = ["workspace_read", "workspace_delete", "workspace_write", "shell_execute", "memory_search"]

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("季度预算为12万元。".utf8).write(to: folder.appendingPathComponent("金边报告.md"))
        try Data("季度预算为8万元。".utf8).write(to: folder.appendingPathComponent("北京报告.md"))
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: folder) }

    private func recalled(_ goal: String, memories: [NexusMemoryItem] = [], history: [ChatMessage] = [],
                          episodes: [NexusTaskEpisode] = []) throws -> [NexusRecallCandidate] {
        try NexusTaskRecall.candidates(goal: goal, memories: memories, knowledge: [], skills: [],
            history: history, episodes: episodes, workspaceRoot: folder)
    }

    func testRealFileRecallAndEngineReadTheNamedChineseObject() async throws {
        let calls = RecallPipelineCalls()
        let control = NexusCognitiveControl(url: folder.appendingPathComponent("governance.json"))
        try control.grantWorkspace()
        defer { try? control.allowAnalysis() }
        var registry = NexusToolRegistry(control: control)
        registry.register(RecallPipelineReader(root: folder, calls: calls))
        var executionRequests = 0
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["读取金边报告"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            return executionRequests == 1
                ? #"{"name":"workspace_read","arguments":{"path":"/workspace/金边报告.md"}}"#
                : "金边报告记载季度预算为12万元，依据工作区读取结果。"
        }, recall: { try self.recalled($0) })
        let outcome = try await engine.run(goal: "核对金边报告")
        XCTAssertTrue(outcome.reviewPassed)
        XCTAssertEqual(engine.intentCard?.objectPath, "/workspace/金边报告.md")
        let observations = await calls.calls
        XCTAssertEqual(observations.map { $0.arguments["path"] }, ["/workspace/金边报告.md"])
        XCTAssertEqual(engine.executor?.toolTraces.first?.result, "季度预算为12万元。")
        XCTAssertTrue(control.state.audit.contains { $0.event == "tool.completed" && $0.subject.hasPrefix("workspace_read:") })
    }

    func testActualTwoFileRecallRequiresOneQuestionBeforeDeletion() async throws {
        var registry = NexusToolRegistry()
        let calls = RecallPipelineCalls()
        registry.register(RecallPipelineReader(root: folder, calls: calls))
        var modelCalls = 0
        let engine = NexusReasoningEngine(tools: registry, model: { _ in
            modelCalls += 1
            return "不应进入模型"
        }, recall: { try self.recalled($0) })
        let outcome = try await engine.run(goal: "删那个")
        XCTAssertTrue(outcome.requiresClarification)
        XCTAssertTrue(outcome.text.contains("哪一个"))
        XCTAssertEqual(modelCalls, 0)
        XCTAssertTrue(engine.intentCard?.allowedTools.isEmpty == true)
        let observations = await calls.calls
        XCTAssertTrue(observations.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("金边报告.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("北京报告.md").path))
    }

    func testConversationEpisodeAndFileNameMergeAsOneObjectWithAllPointers() async throws {
        let goal = "读取金边报告"
        let candidates = try recalled(goal)
        let card = NexusIntentCompiler.compile(goal: goal, candidates: candidates, availableTools: available)
        let call = NexusToolCall(id: UUID(), name: "workspace_read", arguments: ["path": "/workspace/金边报告.md"])
        let trace = NexusToolTrace(stepID: UUID(), round: 1, call: call,
            result: "已观测内容", succeeded: true, timestamp: Date())
        let store = NexusTaskEpisodeStore(url: folder.appendingPathComponent("episodes.json"))
        try store.record(goal: "弄一下那个", card: card, traces: [trace])
        let user = ChatMessage(role: "user", content: "上次处理的是 /workspace/金边报告.md")
        let merged = NexusIntentCompiler.compile(goal: "看看金边报告", candidates:
            try recalled("看看金边报告", history: [user], episodes: store.load()), availableTools: available)
        XCTAssertTrue(merged.isReady)
        XCTAssertEqual(NexusIntentCompiler.normalizedPath(try XCTUnwrap(merged.objectPath)), "金边报告.md")
        XCTAssertTrue(merged.evidenceIDs.contains(NexusEvidenceAudit.toolID(call.id)))
        XCTAssertTrue(merged.evidenceIDs.contains { $0.hasPrefix("conversation:") })
        XCTAssertTrue(merged.evidenceIDs.contains { $0.hasPrefix("workspace-name:") })
        XCTAssertFalse(merged.allowedTools.contains("shell_execute"))
    }

    func testGeneratedMemoryAndWorkspaceContentsCannotBecomeRecallObjects() async throws {
        let invented = "助手猜测她喜欢高风险投资"
        try Data(invented.utf8).write(to: folder.appendingPathComponent("北京报告.md"))
        let memory = NexusMemoryItem(id: UUID(), text: invented, kind: "fact", source: "model",
            confidence: 1, createdAt: Date(), expiresAt: nil, label: "她的偏好")
        let candidates = try recalled("看看那个", memories: [memory],
            history: [ChatMessage(role: "assistant", content: "对象是 /workspace/invented.md")])
        XCTAssertFalse(candidates.contains { $0.source == .confirmedMemory || $0.text.contains(invented) })
        XCTAssertFalse(candidates.contains { $0.objectPath?.contains("invented.md") == true })
        XCTAssertEqual(Set(candidates.compactMap(\.objectPath)), ["/workspace/北京报告.md", "/workspace/金边报告.md"])
    }

    func testRemovedConfirmedMemoryDisappearsFromNewRecallWithoutStaleVectors() async throws {
        let store = NexusMemoryStore(url: folder.appendingPathComponent("memory.json"))
        let id = try store.save(label: "金边偏好", text: "预算报告使用柬埔寨瑞尔。", kind: .preference)
        let before = try recalled("回忆金边偏好", memories: store.curated)
        XCTAssertTrue(before.contains { $0.evidenceID == "memory:" + id.uuidString.lowercased() })
        store.remove(id)
        let after = try recalled("回忆金边偏好", memories: store.curated)
        XCTAssertFalse(after.contains { $0.evidenceID == "memory:" + id.uuidString.lowercased() })
        XCTAssertTrue(store.curated.isEmpty)
    }
}
