import XCTest
@testable import BlackGod

@MainActor
final class NexusCuratedMemoryTests: XCTestCase {
    private var folder: URL!
    private var url: URL { folder.appendingPathComponent("memory.json") }
    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: folder) }

    func testExplicitCorrectionReplacesOldValueAndKeepsIdentityAcrossRestart() throws {
        let memory = NexusMemoryStore(url: url)
        let id = try memory.save(label: "项目名称", text: "Black God 888", kind: .fact)
        let updated = try memory.save(label: "项目名称", text: "Black God，不带数字", kind: .constraint)
        XCTAssertEqual(id, updated)
        let restored = NexusMemoryStore(url: url)
        XCTAssertEqual(restored.curated.count, 1)
        XCTAssertEqual(restored.curated[0].id, id)
        XCTAssertEqual(restored.curated[0].kind, "constraint")
        XCTAssertFalse(restored.context.contains("888"))
        XCTAssertTrue(restored.context.contains("不带数字"))
    }

    func testLabelNormalizationAndRenameCollisionCannotDestroyOtherMemory() throws {
        let memory = NexusMemoryStore(url: url)
        let first = try memory.save(label: "Language", text: "English", kind: .preference)
        XCTAssertEqual(try memory.save(label: " language ", text: "中文", kind: .preference), first)
        let second = try memory.save(label: "项目", text: "Black God", kind: .fact)
        XCTAssertThrowsError(try memory.save(label: "language", text: "覆盖", kind: .fact, replacing: second))
        XCTAssertEqual(memory.curated.count, 2)
        XCTAssertTrue(memory.context.contains("中文"))
    }

    func testLegacyAndAssistantRecordsAreRetainedButNotUsedAsCurrentFacts() throws {
        let old = [NexusMemoryItem(id: UUID(), text: "用户旧原话", kind: "episodic", source: "user", confidence: 0.7, createdAt: Date(), expiresAt: nil),
                   NexusMemoryItem(id: UUID(), text: "模型猜测", kind: "result", source: "assistant", confidence: 0.4, createdAt: Date(), expiresAt: nil)]
        try JSONEncoder().encode(old).write(to: url)
        let memory = NexusMemoryStore(url: url)
        XCTAssertEqual(memory.items.count, 2)
        XCTAssertTrue(memory.curated.isEmpty)
        XCTAssertTrue(memory.context.isEmpty)
        XCTAssertTrue(memory.search("旧原话").isEmpty)
    }

    func testDeleteRemovesMemoryFromLaterContextAndSearchAcrossRestart() throws {
        let memory = NexusMemoryStore(url: url)
        let id = try memory.save(label: "语言", text: "中文", kind: .preference)
        memory.remove(id)
        let restored = NexusMemoryStore(url: url)
        XCTAssertTrue(restored.context.isEmpty)
        XCTAssertTrue(restored.search("语言").isEmpty)
    }

    func testStorageFailureDoesNotClaimEditOrDeleteSucceeded() throws {
        let memory = NexusMemoryStore(url: url)
        let id = try memory.save(label: "名称", text: "Black God", kind: .fact)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try memory.save(label: "名称", text: "新值", kind: .fact))
        memory.remove(id)
        XCTAssertEqual(memory.curated.first?.text, "Black God")
        XCTAssertNotNil(memory.lastError)
    }

    func testCorruptFileIsNotOverwrittenBySave() throws {
        let damaged = Data("[bad JSON".utf8)
        try damaged.write(to: url)
        let memory = NexusMemoryStore(url: url)
        XCTAssertNotNil(memory.lastError)
        XCTAssertThrowsError(try memory.save(label: "语言", text: "中文", kind: .preference))
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }

    func testCapacityFailureKeepsPriorFactsIntact() throws {
        let memory = NexusMemoryStore(url: url)
        for i in 0..<7 { try memory.save(label: "约束\(i)", text: String(repeating: "字", count: 1000), kind: .constraint) }
        XCTAssertThrowsError(try memory.save(label: "约束8", text: String(repeating: "字", count: 1000), kind: .constraint))
        XCTAssertEqual(memory.curated.count, 7)
        XCTAssertEqual(NexusMemoryStore(url: url).curated.count, 7)
    }

    func testExpiredOrFabricatedAssistantCuratedRecordIsNotInjected() throws {
        var expired = NexusMemoryItem(id: UUID(), text: "已过期", kind: "constraint", source: "user", confidence: 1, createdAt: Date(), expiresAt: Date().addingTimeInterval(-1))
        expired.label = "临时约束"
        var invented = NexusMemoryItem(id: UUID(), text: "模型猜测", kind: "fact", source: "assistant", confidence: 1, createdAt: Date(), expiresAt: nil)
        invented.label = "伪造事实"
        try JSONEncoder().encode([expired, invented]).write(to: url)
        XCTAssertTrue(NexusMemoryStore(url: url).context.isEmpty)
    }

    func testLabelIsSearchableEvenWhenValueDoesNotRepeatIt() throws {
        let memory = NexusMemoryStore(url: url)
        try memory.save(label: "交流语言", text: "中文", kind: .preference)
        XCTAssertEqual(memory.search("交流语言").first?.text, "中文")
    }

    func testChatUsesCuratedConstraintsOnUnrelatedPromptAndNeverAutoSavesReplies() async throws {
        let memory = NexusMemoryStore(url: url)
        try memory.save(label: "回复语言", text: "请用中文", kind: .preference)
        memory.remember("旧猜测", source: "assistant")
        var requests: [String] = []
        let vm = ChatViewModel(store: NexusConversationStore(url: folder.appendingPathComponent("chat.json")), memory: memory,
            configured: { _ in true }, completion: { messages, _ in
                requests.append(messages.map(\.content).joined(separator: "\n"))
                return #"{"answer":"你好"}"#
            })
        vm.send("hello")
        try await finish(vm)
        XCTAssertTrue(requests.first?.contains("请用中文") == true)
        XCTAssertFalse(requests.first?.contains("旧猜测") == true)
        XCTAssertEqual(memory.items.count, 2)
        XCTAssertFalse(memory.items.contains { $0.text == "hello" || $0.text == "你好" })
    }

    func testEditingMemoryCancelsActiveTaskAndNextRequestUsesNewValue() async throws {
        let memory = NexusMemoryStore(url: url)
        try memory.save(label: "语言", text: "英文", kind: .preference)
        let started = expectation(description: "model started")
        var requests: [String] = []
        let vm = ChatViewModel(store: NexusConversationStore(url: folder.appendingPathComponent("chat.json")), memory: memory,
            configured: { _ in true }, completion: { messages, _ in
                requests.append(messages.map(\.content).joined(separator: "\n"))
                if requests.count == 1 { started.fulfill(); try await Task.sleep(for: .seconds(30)) }
                return #"{"answer":"你好"}"#
            })
        vm.send("测试")
        await fulfillment(of: [started], timeout: 3)
        try memory.save(label: "语言", text: "中文", kind: .preference)
        XCTAssertFalse(vm.isTyping)
        XCTAssertTrue(vm.canResume)
        vm.send("继续测试")
        try await finish(vm)
        XCTAssertTrue(requests.last?.contains("中文") == true)
        XCTAssertFalse(requests.last?.contains("英文") == true)
        XCTAssertEqual(vm.messages.last?.content, "你好")
    }


    func testFailedReloadStopsExposingPreviouslyLoadedFacts() throws {
        let memory = NexusMemoryStore(url: url)
        try memory.save(label: "语言", text: "英文", kind: .preference)
        try Data("invalid".utf8).write(to: url)
        memory.reload()
        XCTAssertTrue(memory.curated.isEmpty)
        XCTAssertTrue(memory.context.isEmpty)
        XCTAssertNotNil(memory.lastError)
    }

    func testEmptyMemoryIsExplicitWhenResumingAnOldTask() async throws {
        let memory = NexusMemoryStore(url: url)
        let chat = NexusConversationStore(url: folder.appendingPathComponent("chat.json"))
        var record = NexusAgentCheckpoint(id: UUID(), goal: "恢复任务", connection: NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel))
        record.inheritedContext = "旧记忆：语言为英文"
        try NexusAgentCheckpointStore(url: chat.url.deletingPathExtension().appendingPathExtension("agent.json")).save(record)
        var request = ""
        let vm = ChatViewModel(store: chat, memory: memory, configured: { _ in true }, completion: { messages, _ in
            request = messages.map(\.content).joined(separator: "\n")
            return #"{"answer":"继续处理任务"}"#
        })
        vm.resume()
        try await finish(vm)
        XCTAssertTrue(request.contains("当前长期记忆清单为空"))
        XCTAssertTrue(request.contains("旧记忆条目不能视为仍有效"))
    }

    private func finish(_ vm: ChatViewModel) async throws {
        for _ in 0..<200 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(vm.isTyping)
    }
}
