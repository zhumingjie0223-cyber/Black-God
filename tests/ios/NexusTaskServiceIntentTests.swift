import XCTest
@testable import BlackGod

private enum ShortcutIntentFixtureError: Error { case stoppedBeforeExecution }

/// These exercise the actual shortcut entrance and persistence. No provider or Linux command runs.
@MainActor
final class NexusTaskServiceIntentTests: XCTestCase {
    private var folder: URL!
    private var originalLinuxSetting: Any?
    private var originalIntentConnection: String!
    private let source = "shortcut-intent-tests"
    private var checkpoint: NexusAgentCheckpointStore {
        NexusAgentCheckpointStore(url: folder.appendingPathComponent("shortcut.agent.json"))
    }
    private var connection: NexusModelEntry { NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel) }
    private var episodeURL: URL { checkpoint.url.deletingPathExtension().appendingPathExtension("episodes.json") }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        originalLinuxSetting = UserDefaults.standard.object(forKey: "blackgod.linux.modelTools")
        originalIntentConnection = NexusModelRouting.shared.intentConnectionID
        UserDefaults.standard.set(true, forKey: "blackgod.linux.modelTools")
        NexusModelRouting.shared.intentConnectionID = ""
    }

    override func tearDown() async throws {
        if let originalLinuxSetting { UserDefaults.standard.set(originalLinuxSetting, forKey: "blackgod.linux.modelTools") }
        else { UserDefaults.standard.removeObject(forKey: "blackgod.linux.modelTools") }
        NexusModelRouting.shared.intentConnectionID = originalIntentConnection
        try FileManager.default.removeItem(at: folder)
    }

    private func episodes() throws -> [NexusTaskEpisode] {
        let store = NexusTaskEpisodeStore(url: episodeURL)
        if FileManager.default.fileExists(atPath: episodeURL.path) { return try store.load() }
        for (title, path) in [("金边报告", "pp.md"), ("北京报告", "bj.md")] {
            let candidate = NexusRecallCandidate(id: "file:" + path, source: .workspaceFile,
                title: title, text: path, objectPath: path, provenance: "入口测试的已观测文件夹具")
            let card = NexusIntentCompiler.compile(goal: "读取" + title, candidates: [candidate],
                availableTools: ["workspace_read"])
            let call = NexusToolCall(id: UUID(), name: "workspace_read", arguments: ["path": path])
            let trace = NexusToolTrace(stepID: UUID(), round: 1, call: call,
                result: title + "的读取证据", succeeded: true, timestamp: Date())
            try store.record(goal: title, card: card, traces: [trace])
        }
        return try store.load()
    }

    @discardableResult
    private func savePending(sourceID: String?, changedConnection: Bool = false,
                             state: NexusAgentCheckpoint.State = .answered) throws -> NexusIntentCard {
        let candidates = try episodes().map(\.candidate)
        let card = NexusIntentCompiler.compile(goal: "删除那个", candidates: candidates,
            availableTools: ["workspace_delete", "workspace_read", "memory_search", "clock", "calc"])
        XCTAssertTrue(card.missingSlots.contains("object"))
        var target = connection
        if changedConnection { target.connectionID = "fixture-different-account" }
        var saved = NexusAgentCheckpoint(id: UUID(), goal: card.goal, connection: target)
        saved.state = state; saved.sourceID = sourceID
        saved.intentCard = card; saved.needsClarification = true
        try checkpoint.save(saved)
        return card
    }

    private func ask(_ goal: String, completion: @escaping ([ChatMessage], String) async throws -> String) async throws -> String {
        try await NexusTaskService.ask(goal, source: source,
            cognitive: NexusCognitiveControl(url: folder.appendingPathComponent("cognitive.json")),
            memory: NexusMemoryStore(url: folder.appendingPathComponent("memory.json")),
            skills: NexusSkillStore(url: folder.appendingPathComponent("skills.json")),
            checkpointURL: checkpoint.url, configured: { _ in true }, completion: completion,
            nativeCompletion: { _, _, _ in
                XCTFail("This fixture must stop before native execution.")
                throw ShortcutIntentFixtureError.stoppedBeforeExecution
            })
    }

    func testFirstClarificationSavesOriginalCardAndSourceWithoutCallingModel() async throws {
        _ = try episodes()
        var calls = 0
        let question = try await ask("删除那个") { _, _ in calls += 1; return "不应请求模型" }
        let saved = try XCTUnwrap(checkpoint.load())
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(question.contains("哪一个"))
        XCTAssertEqual(saved.intentCard?.goal, "删除那个")
        XCTAssertEqual(saved.intentCard?.operation, .delete)
        XCTAssertEqual(saved.sourceID, source)
        XCTAssertEqual(saved.needsClarification, true)
        XCTAssertNil(saved.plan)
        XCTAssertTrue(saved.evidence.isEmpty)
    }

    func testShortAnswerContinuesOnlyOriginalActionAndSelectedPath() async throws {
        let pending = try savePending(sourceID: source)
        var requests: [String] = []
        do {
            _ = try await ask("pp.md") { messages, _ in
                requests.append(messages.last?.content ?? "")
                throw ShortcutIntentFixtureError.stoppedBeforeExecution
            }
            XCTFail("The fixture should stop after compiling and before executing.")
        } catch ShortcutIntentFixtureError.stoppedBeforeExecution {}
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].contains(#""operation":"delete""#))
        XCTAssertTrue(requests[0].contains(#""objectPath":"pp.md""#))
        let saved = try XCTUnwrap(checkpoint.load())
        XCTAssertEqual(saved.clarificationIntent, pending)
        XCTAssertEqual(saved.sourceID, source)
        XCTAssertTrue(saved.evidence.isEmpty)
    }

    func testMissingCapabilityRemainsClarificationWithZeroModelCalls() async throws {
        _ = try savePending(sourceID: source)
        UserDefaults.standard.set(false, forKey: "blackgod.linux.modelTools")
        var calls = 0
        let answer = try await ask("pp.md") { _, _ in calls += 1; return "不应请求模型" }
        let saved = try XCTUnwrap(checkpoint.load())
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(answer.contains("可用工具"))
        XCTAssertEqual(saved.intentCard?.operation, .delete)
        XCTAssertEqual(saved.intentCard?.objectPath, "pp.md")
        XCTAssertEqual(saved.intentCard?.goal, "删除那个")
        XCTAssertTrue(saved.intentCard?.missingSlots.contains("capability") == true)
        XCTAssertEqual(saved.needsClarification, true)
        XCTAssertTrue(saved.evidence.isEmpty)
    }

    func testDifferentSourceConnectionLegacySourceAndDiscardedTaskDoNotContinueDeletion() async throws {
        for scenario in 0..<4 {
            _ = try savePending(sourceID: scenario == 0 ? "other-shortcut" : scenario == 2 ? nil : source,
                changedConnection: scenario == 1, state: scenario == 3 ? .discarded : .answered)
            var calls = 0
            _ = try await ask("pp.md") { _, _ in calls += 1; return #"{"answer":"这是本次的新请求。"}"# }
            let saved = try XCTUnwrap(checkpoint.load())
            XCTAssertEqual(calls, 1, "scenario \(scenario)")
            XCTAssertEqual(saved.intentCard?.operation, .respond, "scenario \(scenario)")
            XCTAssertNil(saved.clarificationIntent, "scenario \(scenario)")
            XCTAssertEqual(saved.sourceID, source)
            XCTAssertTrue(saved.evidence.isEmpty)
        }
    }

    func testUnreadableCheckpointIsNotOverwrittenAndDoesNotCallModel() async throws {
        let original = Data("{broken-shortcut-checkpoint".utf8)
        try original.write(to: checkpoint.url)
        var calls = 0
        do {
            _ = try await ask("pp.md") { _, _ in calls += 1; return "不应请求模型" }
            XCTFail("An unreadable checkpoint must block replacement.")
        } catch let error as NexusTaskServiceError {
            XCTAssertTrue(error.localizedDescription.contains("原记录已保留"))
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try Data(contentsOf: checkpoint.url), original)
    }
}
