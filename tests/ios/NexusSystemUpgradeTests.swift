import XCTest
@testable import BlackGod

@MainActor
final class NexusSystemUpgradeTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testContextCompactionKeepsRecentAndConstraintHints() {
        var messages: [ChatMessage] = [
            ChatMessage(role: "user", content: "项目名称必须是 Black God，不要再写数字。"),
            ChatMessage(role: "assistant", content: "好的，记住了。")
        ]
        for i in 0..<30 {
            messages.append(ChatMessage(role: "user", content: "闲聊\(i) " + String(repeating: "话", count: 200)))
            messages.append(ChatMessage(role: "assistant", content: "回\(i)"))
        }
        messages.append(ChatMessage(role: "user", content: "最新要求：只输出项目名"))
        let pack = NexusContextBudget.compact(messages, maxCharacters: 1200)
        XCTAssertNotNil(pack.summary)
        XCTAssertTrue(pack.droppedCount > 0)
        XCTAssertEqual(pack.messages.last?.content, "最新要求：只输出项目名")
        XCTAssertTrue(pack.summary?.contains("Black God") == true || pack.summary?.contains("必须") == true)
        XCTAssertTrue(pack.summary?.contains("不能覆盖最新用户要求") == true)
        XCTAssertLessThanOrEqual(pack.messages.reduce(0) { $0 + $1.content.count }, 1200)
    }

    func testCrossSessionSearchFindsMessageAndVaultExportWipe() throws {
        let library = NexusSessionLibrary(root: folder)
        let first = try library.bootstrap().activeID
        try library.conversationStore(for: first).save([
            ChatMessage(role: "user", content: "苹果园灌溉计划"),
            ChatMessage(role: "assistant", content: "已记下灌溉")
        ])
        _ = try library.touch(first, messages: try library.conversationStore(for: first).load())
        let second = try library.create(title: "别的")
        try library.conversationStore(for: second.id).save([ChatMessage(role: "user", content: "香蕉清单")])

        let hits = try library.search("灌溉")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].sessionID, first)
        XCTAssertTrue(hits[0].snippet.contains("灌溉"))

        let memory = NexusMemoryStore(url: folder.appendingPathComponent("nexus-memory.json"))
        _ = try memory.save(label: "称呼", text: "权哥", kind: .preference)
        let skills = NexusSkillStore(url: folder.appendingPathComponent("nexus-skills.json"))
        let vault = NexusDataVault(root: folder)
        let data = try vault.exportAll(memory: memory.curated, skills: skills.items)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(NexusVaultExport.self, from: data)
        XCTAssertEqual(payload.format, "blackgod.vault.v1")
        XCTAssertEqual(payload.sessions.count, 2)
        XCTAssertEqual(payload.memory.count, 1)

        XCTAssertThrowsError(try vault.wipeConversations(confirm: "随便")) { error in
            XCTAssertEqual(error as? NexusDataVaultError, .confirmMismatch)
        }
        try vault.wipeConversations(confirm: NexusDataVault.wipePhrase)
        let after = try library.bootstrap()
        XCTAssertEqual(after.sessions.count, 1)
        XCTAssertTrue(try library.conversationStore(for: after.activeID).load().isEmpty)
        XCTAssertEqual(memory.curated.count, 1)
    }

    func testSharedTaskServiceUsesMemoryAndCheckpoint() async throws {
        let memoryURL = folder.appendingPathComponent("nexus-memory.json")
        let memory = NexusMemoryStore(url: memoryURL)
        _ = try memory.save(label: "主题色", text: "青绿色", kind: .preference)
        let checkpoint = folder.appendingPathComponent("shortcuts.agent.json")
        var seenPrompt = ""
        let cognitive = NexusCognitiveControl(url: folder.appendingPathComponent("cognitive.json"))
        let answer = try await NexusTaskService.ask(
            "主题色是什么",
            source: "shortcuts-test",
            cognitive: cognitive,
            memory: memory,
            skills: NexusSkillStore(url: folder.appendingPathComponent("skills.json")),
            checkpointURL: checkpoint,
            configured: { _ in true },
            completion: { messages, _ in
                seenPrompt = messages.last?.content ?? ""
                if seenPrompt.contains("[任务规划]") {
                    return #"{"answer":"青绿色","steps":[],"successCriteria":["正确颜色"]}"#
                }
                if seenPrompt.contains("[结果复核]") {
                    return #"{"passed":true,"issues":[]}"#
                }
                return #"{"answer":"青绿色"}"#
            }
        )
        XCTAssertTrue(answer.contains("青绿"))
        XCTAssertTrue(seenPrompt.contains("青绿色") || seenPrompt.contains("主题色"))
        let saved = try NexusAgentCheckpointStore(url: checkpoint).load()
        XCTAssertEqual(saved?.goal, "主题色是什么")
        XCTAssertEqual(saved?.state, .answered)
    }
}
