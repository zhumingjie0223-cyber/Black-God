import XCTest
@testable import BlackGod

@MainActor
final class NexusConversationLifecycleTests: XCTestCase {
    private var folder: URL!
    private var conversation: NexusConversationStore { NexusConversationStore(url: folder.appendingPathComponent("chat.json")) }
    private var checkpoint: NexusAgentCheckpointStore { NexusAgentCheckpointStore(url: folder.appendingPathComponent("chat.agent.json")) }
    private var connection: NexusModelEntry { NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel) }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try FileManager.default.removeItem(at: folder) }

    func testClearRemovesConversationAndRecoveryWithoutRevivingAnswer() async throws {
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in #"{"answer":"保留到清空前的回答"}"# })
        vm.send("问题")
        try await finish(vm)
        XCTAssertTrue(vm.canClearConversation)
        XCTAssertTrue(vm.live.visible)
        XCTAssertTrue(vm.clearConversation())
        XCTAssertFalse(vm.canClearConversation)
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(vm.taskCheckpoint)
        XCTAssertFalse(vm.live.visible)
        XCTAssertNil(try checkpoint.load())
        XCTAssertTrue(try conversation.load().isEmpty)
        let restarted = ChatViewModel(store: conversation)
        XCTAssertTrue(restarted.messages.isEmpty)
        XCTAssertFalse(restarted.canResume)
        XCTAssertFalse(restarted.canRegenerate)
    }

    func testClearCancelsPendingReplyAndLateCompletionCannotRestoreIt() async throws {
        var held: CheckedContinuation<String, Never>?
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in
            await withCheckedContinuation { held = $0 }
        })
        vm.send("旧问题")
        for _ in 0..<200 where held == nil { try await Task.sleep(for: .milliseconds(10)) }
        let pending = try XCTUnwrap(held)
        XCTAssertTrue(vm.clearConversation())
        pending.resume(returning: #"{"answer":"迟到的旧回答"}"#)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(try checkpoint.load())
        XCTAssertTrue(ChatViewModel(store: conversation).messages.isEmpty)
    }

    func testInterruptedClearFinishesBeforeCheckpointRecovery() throws {
        let old = ChatMessage(role: "assistant", content: "不应复活")
        try conversation.save([old])
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "旧任务", connection: connection)
        saved.state = .answered; saved.finalMessage = old
        try checkpoint.save(saved)
        try Data("clear-v1".utf8).write(to: conversation.clearIntentURL)
        let vm = ChatViewModel(store: conversation)
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(vm.taskCheckpoint)
        XCTAssertNil(try checkpoint.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: conversation.clearIntentURL.path))
    }

    func testFailedClearReportsFailureAndBlocksNewWritesUntilRetried() throws {
        try conversation.save([ChatMessage(role: "user", content: "原消息")])
        let vm = ChatViewModel(store: conversation, configured: { _ in true })
        try FileManager.default.removeItem(at: conversation.url)
        try FileManager.default.createDirectory(at: conversation.url, withIntermediateDirectories: true)
        XCTAssertFalse(vm.clearConversation())
        XCTAssertEqual(vm.messages.first?.content, "原消息")
        XCTAssertTrue(vm.lastError?.contains("未完成") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: conversation.clearIntentURL.path))
        vm.send("不能覆盖")
        XCTAssertFalse(vm.isTyping)
        XCTAssertEqual(vm.messages.count, 1)
        try FileManager.default.removeItem(at: conversation.url)
        XCTAssertTrue(vm.clearConversation())
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertTrue(try conversation.load().isEmpty)
    }

    func testCorruptConversationAndCheckpointAreNeverOverwrittenBySending() throws {
        let brokenChat = Data("{broken-chat".utf8)
        let brokenTask = Data("{broken-task".utf8)
        try brokenChat.write(to: conversation.url)
        try brokenTask.write(to: checkpoint.url)
        var calls = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in calls += 1; return "不会请求" })
        vm.send("新问题")
        XCTAssertFalse(vm.isTyping)
        XCTAssertFalse(vm.canResume)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try Data(contentsOf: conversation.url), brokenChat)
        XCTAssertEqual(try Data(contentsOf: checkpoint.url), brokenTask)
        XCTAssertTrue(vm.clearConversation())
        let backupRoot = folder.appendingPathComponent("ConversationRecovery")
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("chat.json")), brokenChat)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("chat.agent.json")), brokenTask)
        XCTAssertTrue(try conversation.load().isEmpty)
        XCTAssertNil(try checkpoint.load())
    }

    func testUnreadableCheckpointDirectoryBlocksSendingUntilExplicitClear() throws {
        try FileManager.default.createDirectory(at: checkpoint.url, withIntermediateDirectories: true)
        let sentinel = checkpoint.url.appendingPathComponent("preserved.txt")
        try Data("original".utf8).write(to: sentinel)
        var calls = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in calls += 1; return "不会请求" })
        vm.send("新任务")
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(vm.isTyping)
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertTrue(vm.lastError?.contains("已保留原文件") == true)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("original".utf8))
        XCTAssertTrue(vm.clearConversation())
        let backupRoot = folder.appendingPathComponent("ConversationRecovery")
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("chat.agent.json/preserved.txt")), Data("original".utf8))
        XCTAssertNil(try checkpoint.load())
    }

    func testCorruptConversationIsNotOverwrittenByValidFinalCheckpoint() throws {
        let broken = Data("{broken-chat".utf8)
        try broken.write(to: conversation.url)
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "原任务", connection: connection)
        saved.state = .answered; saved.finalMessage = ChatMessage(role: "assistant", content: "可恢复回答")
        try checkpoint.save(saved)
        let vm = ChatViewModel(store: conversation)
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertEqual(try Data(contentsOf: conversation.url), broken)
        XCTAssertEqual(try checkpoint.load()?.finalMessage?.content, "可恢复回答")
    }

    func testFailedCorruptFileBackupPreventsClear() throws {
        let broken = Data("{broken-chat".utf8)
        try broken.write(to: conversation.url)
        try Data("blocked backup directory".utf8).write(to: folder.appendingPathComponent("ConversationRecovery"))
        let vm = ChatViewModel(store: conversation)
        XCTAssertFalse(vm.clearConversation())
        XCTAssertEqual(try Data(contentsOf: conversation.url), broken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: conversation.clearIntentURL.path))
        XCTAssertNotNil(vm.lastError)
    }

    func testRegeneratePreservesAnswerWhenConnectionIsUnavailable() async throws {
        var configured = true
        var calls = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in configured }, completion: { _, _ in calls += 1; return #"{"answer":"第一版"}"# })
        vm.send("问题")
        try await finish(vm)
        let old = try XCTUnwrap(vm.messages.last)
        configured = false
        vm.regenerate()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(vm.messages.last?.id, old.id)
        XCTAssertEqual(try conversation.load().last?.id, old.id)
        XCTAssertEqual(ChatViewModel(store: conversation).messages.last?.id, old.id)
    }

    func testFailedRegenerationKeepsOriginalUntilSuccessfulResume() async throws {
        var calls = 0
        var requestHistory: [[ChatMessage]] = []
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { messages, _ in
            calls += 1; requestHistory.append(messages)
            if calls == 2 { throw URLError(.notConnectedToInternet) }
            return calls == 1 ? #"{"answer":"第一版"}"# : #"{"answer":"第二版"}"#
        })
        vm.send("问题")
        try await finish(vm)
        let original = try XCTUnwrap(vm.messages.last)
        vm.regenerate()
        try await finish(vm)
        XCTAssertEqual(vm.messages.last?.id, original.id)
        XCTAssertEqual(try conversation.load().last?.id, original.id)
        XCTAssertFalse(requestHistory[1].contains { $0.id == original.id })
        XCTAssertTrue(vm.canResume)
        XCTAssertEqual(try checkpoint.load()?.replacingMessageID, original.id)
        vm.resume()
        try await finish(vm)
        XCTAssertEqual(vm.messages.filter { $0.role == "assistant" }.map(\.content), ["第二版"])
        XCTAssertEqual(vm.messages.filter { $0.role == "user" }.count, 1)
        XCTAssertEqual(ChatViewModel(store: conversation).messages.filter { $0.role == "assistant" }.map(\.content), ["第二版"])
    }

    func testRestartKeepsOriginalDuringInterruptedRegeneration() throws {
        let original = ChatMessage(role: "assistant", content: "第一版")
        try conversation.save([ChatMessage(role: "user", content: "问题"), original])
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "问题", connection: connection)
        saved.replacingMessageID = original.id
        try checkpoint.save(saved)
        let vm = ChatViewModel(store: conversation)
        XCTAssertEqual(vm.messages.last?.id, original.id)
        XCTAssertTrue(vm.canResume)
        XCTAssertEqual(vm.taskCheckpoint?.state, .interrupted)
    }

    func testFailedReplacementWriteKeepsOriginalAndNewReplyRemainsRecoverable() async throws {
        var calls = 0
        let vm = ChatViewModel(store: conversation, configured: { _ in true }, completion: { _, _ in
            calls += 1
            if calls == 2 {
                try FileManager.default.removeItem(at: self.conversation.url)
                try FileManager.default.createDirectory(at: self.conversation.url, withIntermediateDirectories: true)
            }
            return calls == 1 ? #"{"answer":"第一版"}"# : #"{"answer":"第二版"}"#
        })
        vm.send("问题")
        try await finish(vm)
        let original = try XCTUnwrap(vm.messages.last)
        vm.regenerate()
        try await finish(vm)
        XCTAssertEqual(vm.messages.last?.id, original.id)
        XCTAssertTrue(vm.lastError?.contains("保存历史记录失败") == true)
        XCTAssertEqual(try checkpoint.load()?.finalMessage?.content, "第二版")
        try FileManager.default.removeItem(at: conversation.url)
        try conversation.save(vm.messages)
        let restored = ChatViewModel(store: conversation)
        XCTAssertEqual(restored.messages.filter { $0.role == "assistant" }.map(\.content), ["第二版"])
    }

    func testFinalRegeneratedReplyReplacesOriginalExactlyOnceAfterPartialCommit() throws {
        let original = ChatMessage(role: "assistant", content: "第一版")
        let replacement = ChatMessage(role: "assistant", content: "第二版")
        try conversation.save([ChatMessage(role: "user", content: "问题"), original])
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "问题", connection: connection)
        saved.state = .answered; saved.replacingMessageID = original.id; saved.finalMessage = replacement
        try checkpoint.save(saved)
        for _ in 0..<2 {
            let vm = ChatViewModel(store: conversation)
            XCTAssertEqual(vm.messages.filter { $0.role == "assistant" }.map(\.id), [replacement.id])
            XCTAssertTrue(vm.canRegenerate)
        }
    }

    private func finish(_ vm: ChatViewModel) async throws {
        for _ in 0..<200 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(vm.isTyping)
    }
}
