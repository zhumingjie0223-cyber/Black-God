import Foundation
import XCTest
@testable import BlackGod

/// 使用真实聊天入口检查恢复边界；便携包也执行状态断言，订阅与界面仍由 Xcode 验证。
@MainActor
final class NexusChatRecoveryTests: XCTestCase {
    private var folder: URL!
    private var conversation: NexusConversationStore { .init(url: folder.appendingPathComponent("chat.json")) }
    private var checkpoint: NexusAgentCheckpointStore { .init(url: folder.appendingPathComponent("chat.agent.json")) }
    private var connection: NexusModelEntry { NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel) }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: folder) }

    private func interruptedCommand() -> NexusAgentCheckpoint {
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "执行命令：pwd", connection: connection)
        saved.intentCard = NexusIntentCompiler.compile(goal: saved.goal, candidates: [], availableTools: ["shell_execute"])
        saved.pendingTool = "shell_execute"
        saved.state = .interrupted
        return saved
    }

    func testResumeOfInterruptedCommandStopsBeforeAnyModelAndPersistsRecoveryBoundary() async throws {
        let original = interruptedCommand()
        try checkpoint.save(original)
        var calls = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in
            calls += 1
            return #"{"answer":"不应执行"}"#
        })
        XCTAssertTrue(vm.canResume)
        vm.resume()
        try await finish(vm)
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(vm.canResume)
        XCTAssertFalse(vm.canRegenerate)
        XCTAssertEqual(vm.messages.filter { $0.role == "user" }.count, 0)
        let saved = try XCTUnwrap(checkpoint.load())
        XCTAssertEqual(saved.state, .answered)
        XCTAssertEqual(saved.recoveryPolicy?.protectedOperation, .execute)
        XCTAssertEqual(saved.needsClarification, false)
        XCTAssertTrue(saved.finalMessage?.content.contains("完整操作指令") == true)
    }

    func testRegenerationInheritsProgramBoundaryAfterCardHasBecomeReadOnly() async throws {
        let original = interruptedCommand()
        var recovered = NexusAgentCheckpoint(id: UUID(), goal: "你好", connection: connection)
        recovered.recoveryPolicy = NexusRecoveryPolicy(checkpoint: original)
        recovered.intentCard = NexusIntentCompiler.compile(goal: "你好", candidates: [], availableTools: ["calc"])
        recovered.state = .answered
        recovered.finalMessage = .init(role: "assistant", content: "上次恢复只检查了记录。")
        try checkpoint.save(recovered)
        var calls = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in
            calls += 1
            return #"{"answer":"不应执行"}"#
        })
        XCTAssertTrue(vm.canRegenerate)
        vm.regenerate()
        try await finish(vm)
        XCTAssertEqual(calls, 0)
        let saved = try XCTUnwrap(checkpoint.load())
        XCTAssertEqual(saved.recoveryPolicy?.protectedOperation, .execute)
        XCTAssertEqual(saved.needsClarification, false)
        XCTAssertEqual(vm.messages.filter { $0.role == "assistant" }.count, 1)
    }

    func testShortContinueReplyDoesNotFillOldCommandAuthorization() async throws {
        try checkpoint.save(interruptedCommand())
        var calls = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in
            calls += 1
            return #"{"answer":"请发送需要处理的具体对象与操作。"}"#
        })
        vm.resume()
        try await finish(vm)
        XCTAssertEqual(calls, 0)
        vm.send("继续")
        try await finish(vm)
        let saved = try XCTUnwrap(checkpoint.load())
        XCTAssertNil(saved.recoveryPolicy)
        XCTAssertNil(saved.clarificationIntent)
        XCTAssertEqual(saved.intentCard?.operation, .respond)
        XCTAssertFalse(saved.intentCard?.allowedTools.contains("shell_execute") ?? true)
        XCTAssertTrue(saved.evidence.isEmpty)
        XCTAssertEqual(calls, 1)
    }

    private func finish(_ vm: ChatViewModel) async throws {
        for _ in 0..<300 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(vm.isTyping)
    }
}
