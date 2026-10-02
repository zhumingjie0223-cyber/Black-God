import XCTest
@testable import BlackGod

@MainActor
final class NexusSessionLibraryTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testBootstrapCreatesEmptyActiveSession() throws {
        let library = NexusSessionLibrary(root: folder)
        let index = try library.bootstrap()
        XCTAssertEqual(index.sessions.count, 1)
        XCTAssertEqual(index.activeID, index.sessions[0].id)
        XCTAssertTrue(try library.conversationStore(for: index.activeID).load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("nexus-conversation.json").path))
    }

    func testMigratesLegacyConversationAndCheckpoint() throws {
        let legacy = NexusConversationStore(url: folder.appendingPathComponent("nexus-conversation.json"))
        let checkpoint = NexusAgentCheckpointStore(url: folder.appendingPathComponent("nexus-conversation.agent.json"))
        let user = ChatMessage(role: "user", content: "旧对话主题很长很长很长很长很长很长很长很长")
        try legacy.save([user, ChatMessage(role: "assistant", content: "旧回答")])
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "旧对话主题", connection: NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel))
        saved.state = .answered
        try checkpoint.save(saved)

        let library = NexusSessionLibrary(root: folder)
        let index = try library.bootstrap()
        XCTAssertEqual(index.sessions.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpoint.url.path))
        let messages = try library.conversationStore(for: index.activeID).load()
        XCTAssertEqual(messages.map(\.content), [user.content, "旧回答"])
        XCTAssertEqual(try library.checkpointStore(for: index.activeID).load()?.goal, "旧对话主题")
        XCTAssertTrue(index.sessions[0].title.hasPrefix("旧对话主题"))
        XCTAssertTrue(index.sessions[0].title.hasSuffix("…") || index.sessions[0].title == NexusSessionRecord.cleanTitle(user.content))
    }

    func testCreateSwitchDeleteAndExportKeepIsolation() throws {
        let library = NexusSessionLibrary(root: folder)
        let first = try library.bootstrap().activeID
        try library.conversationStore(for: first).save([ChatMessage(role: "user", content: "会话甲")])
        _ = try library.touch(first, messages: try library.conversationStore(for: first).load())

        let second = try library.create(title: "会话乙")
        try library.conversationStore(for: second.id).save([ChatMessage(role: "user", content: "会话乙内容")])
        XCTAssertEqual(try library.activeID(), second.id)
        XCTAssertEqual(try library.conversationStore(for: first).load().map(\.content), ["会话甲"])
        XCTAssertEqual(try library.conversationStore(for: second.id).load().map(\.content), ["会话乙内容"])

        _ = try library.select(first)
        XCTAssertEqual(try library.activeID(), first)

        let json = try library.export(first)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(NexusSessionExport.self, from: json)
        XCTAssertEqual(payload.format, "blackgod.session.v1")
        XCTAssertEqual(payload.messages.map(\.content), ["会话甲"])
        XCTAssertTrue(try library.exportPlainText(first).contains("会话甲"))

        let afterDelete = try library.delete(second.id)
        XCTAssertEqual(afterDelete.sessions.count, 1)
        XCTAssertEqual(afterDelete.activeID, first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.conversationURL(for: second.id).path))
    }

    func testCannotDeleteLastSessionAndRespectsLimit() throws {
        let library = NexusSessionLibrary(root: folder)
        let only = try library.bootstrap().activeID
        XCTAssertThrowsError(try library.delete(only)) { error in
            XCTAssertEqual((error as? NexusSessionError), .cannotDeleteLast)
        }
        for _ in 0..<(NexusSessionLibrary.maxSessions - 1) {
            _ = try library.create()
        }
        XCTAssertEqual(try library.list().count, NexusSessionLibrary.maxSessions)
        XCTAssertThrowsError(try library.create()) { error in
            XCTAssertEqual((error as? NexusSessionError), .limitReached)
        }
    }

    func testViewModelKeepsSessionsIsolatedAndExports() async throws {
        let library = NexusSessionLibrary(root: folder)
        let first = try library.bootstrap().sessions[0]
        let vm = ChatViewModel(
            store: library.conversationStore(for: first.id),
            sessions: library,
            configured: { _ in true },
            completion: { _, _ in #"{"answer":"甲回答"}"# }
        )
        XCTAssertTrue(vm.supportsSessions)
        XCTAssertEqual(vm.activeSessionID, first.id)
        vm.send("会话甲问题")
        try await finish(vm)
        XCTAssertEqual(vm.messages.last?.content, "甲回答")

        XCTAssertTrue(vm.createSession())
        let secondID = try XCTUnwrap(vm.activeSessionID)
        XCTAssertNotEqual(secondID, first.id)
        XCTAssertTrue(vm.messages.isEmpty)
        vm.send("会话乙问题")
        try await finish(vm)
        XCTAssertEqual(vm.messages.filter { $0.role == "user" }.map(\.content), ["会话乙问题"])

        XCTAssertTrue(vm.switchSession(first.id))
        XCTAssertEqual(vm.messages.filter { $0.role == "user" }.map(\.content), ["会话甲问题"])
        XCTAssertEqual(vm.messages.last?.content, "甲回答")

        let exported = try vm.exportSessionJSON(first.id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(NexusSessionExport.self, from: exported)
        XCTAssertEqual(payload.messages.filter { $0.role == "user" }.map(\.content), ["会话甲问题"])
        XCTAssertTrue(try vm.exportSessionText(secondID).contains("会话乙问题"))

        XCTAssertTrue(vm.deleteSession(secondID))
        XCTAssertEqual(vm.activeSessionID, first.id)
        XCTAssertEqual(vm.sessions.count, 1)
    }

    func testCustomStoreWithoutLibraryKeepsSingleFileBehavior() throws {
        let store = NexusConversationStore(url: folder.appendingPathComponent("chat.json"))
        try store.save([ChatMessage(role: "user", content: "单文件")])
        let vm = ChatViewModel(store: store, configured: { _ in false })
        XCTAssertFalse(vm.supportsSessions)
        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertEqual(vm.messages.map(\.content), ["单文件"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("nexus-sessions.json").path))
    }

    private func finish(_ vm: ChatViewModel) async throws {
        for _ in 0..<200 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(vm.isTyping)
    }
}
