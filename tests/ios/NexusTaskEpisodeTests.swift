import Foundation
import XCTest
@testable import BlackGod

@MainActor
final class NexusTaskEpisodeTests: XCTestCase {
    private var folder: URL!
    private var store: NexusTaskEpisodeStore { .init(url: folder.appendingPathComponent("episodes.json")) }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: folder) }

    private func trace(_ name: String = "workspace_read", output: String = "已观测文件内容",
                       succeeded: Bool = true, denied: Bool = false, path: String? = "/workspace/report.md") -> NexusToolTrace {
        NexusToolTrace(stepID: UUID(), round: 1,
            call: .init(id: UUID(), name: name, arguments: path.map { ["path": $0] } ?? [:]),
            result: output, succeeded: succeeded, timestamp: Date(), authorizationDenied: denied)
    }

    private func card() -> NexusIntentCard {
        let file = NexusRecallCandidate(id: "file:report", source: .workspaceFile, title: "report.md", text: "report.md",
            objectPath: "/workspace/report.md", provenance: "工作区目录")
        return NexusIntentCompiler.compile(goal: "读取report.md", candidates: [file], availableTools: ["workspace_read"])
    }

    func testRealPersistenceReloadRetainsObservedEvidenceAndStableSourcePointers() async throws {
        let observation = trace(output: "文件数值为17")
        try store.record(goal: "读取report.md", card: card(), traces: [observation])
        let restored = try XCTUnwrap(NexusTaskEpisodeStore(url: store.url).load().first)
        XCTAssertEqual(restored.goal, "读取report.md")
        XCTAssertEqual(restored.objectPath, "/workspace/report.md")
        XCTAssertEqual(restored.evidenceIDs, [NexusEvidenceAudit.toolID(observation.call.id)])
        XCTAssertEqual(restored.observations?.map(\.id), restored.evidenceIDs)
        XCTAssertEqual(restored.observations?.first?.output, "文件数值为17")
        XCTAssertEqual(restored.observations?.first?.scope, "path=/workspace/report.md")
        XCTAssertEqual(restored.candidate.source, .taskSummary)
        XCTAssertEqual(restored.candidate.evidencePointers, restored.evidenceIDs)
        XCTAssertEqual(restored.candidate.evidenceID, "task:" + restored.id.uuidString.lowercased())
        XCTAssertFalse(restored.candidate.isGenerated)
    }

    func testTaskCandidateNeverIndexesGeneratedConclusionOrObservedFileBodyAsPreference() async throws {
        try store.record(goal: "检查report.md", card: card(), traces: [trace(output: "模型推断：她喜欢高风险投资")])
        let episode = try XCTUnwrap(store.load().first)
        XCTAssertFalse(episode.candidate.text.contains("高风险投资"))
        XCTAssertFalse(episode.candidate.text.contains("模型推断"))
        XCTAssertEqual(episode.observations?.first?.output, "模型推断：她喜欢高风险投资")
        let index = NexusRecallIndex(candidates: [episode.candidate], embedding: nil)
        XCTAssertTrue(index.recall(query: "高风险投资").isEmpty)
    }

    func testFailedDeniedAndGovernanceOnlyEventsDoNotCreateAnEpisode() async throws {
        try store.record(goal: "检查report.md", card: card(), traces: [
            trace(succeeded: false), trace(denied: true), trace("plan"), trace("verify"),
            trace("knowledge_propose"), trace("self_reflect")
        ])
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testBoundedEvidenceSnapshotsResolveEverySavedPointer() async throws {
        let traces = (0..<30).map { trace(output: "观测\($0)") }
        try store.record(goal: "检查report.md", card: card(), traces: traces)
        let episode = try XCTUnwrap(store.load().first)
        XCTAssertEqual(episode.evidenceIDs.count, 24)
        XCTAssertEqual(episode.observations?.count, 24)
        XCTAssertEqual(Set(episode.evidenceIDs), Set(episode.observations?.map(\.id) ?? []))
        XCTAssertEqual(episode.evidenceIDs.first, NexusEvidenceAudit.toolID(traces[6].call.id))
    }

    func testRedactionRunsBeforeGoalAndOutputTruncationAndStaysReloadable() async throws {
        let secret = "sk-secret-123456789"
        let goal = String(repeating: "a", count: 495) + secret + "末尾"
        let output = String(repeating: "b", count: 560) + secret + String(repeating: "c", count: 2000)
        try store.record(goal: goal, card: card(), traces: [trace(output: output)], redacting: [secret])
        let bytes = String(decoding: try Data(contentsOf: store.url), as: UTF8.self)
        XCTAssertFalse(bytes.contains(secret))
        XCTAssertFalse(bytes.contains("sk-se"), "先截断会留下无法匹配完整secret的凭据片段")
        let restored = try XCTUnwrap(store.load().first)
        XCTAssertLessThanOrEqual(restored.goal.count, 500)
        XCTAssertLessThanOrEqual(restored.observations?.first?.output.count ?? 0, 1200)
        try store.record(goal: String(repeating: "key", count: 166), card: card(), traces: [trace()], redacting: ["key"])
        XCTAssertEqual(try store.load().count, 2, "脱敏字符串扩长也不能产生record成功却reload失败的文件")
    }

    func testCorruptEpisodeStoreIsPreservedInsteadOfOverwritten() async throws {
        let corrupt = Data("[broken-json".utf8)
        try corrupt.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.record(goal: "检查report.md", card: card(), traces: [trace()]))
        XCTAssertEqual(try Data(contentsOf: store.url), corrupt)
    }

    func testMissingOrMismatchedObservationPointersCannotReviveAnEpisode() async throws {
        try store.record(goal: "读取report.md", card: card(), traces: [trace()])
        let valid = try store.load()
        for hasSnapshot in [false, true] {
            var unsupported = valid
            unsupported[0].observations = hasSnapshot ? [NexusEvidenceRecord(id: "tool:unresolvable", stepID: UUID(),
                tool: "workspace_read", succeeded: true, output: "没有对应原始调用")] : nil
            let originalBytes = try JSONEncoder().encode(unsupported)
            try originalBytes.write(to: store.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.record(goal: "读取report.md", card: card(), traces: [trace()]))
            XCTAssertEqual(try Data(contentsOf: store.url), originalBytes)
        }
    }

    func testConversationClearRemovesEpisodesAndRestartCannotRecallThem() async throws {
        let conversation = NexusConversationStore(url: folder.appendingPathComponent("chat.json"))
        let episodes = NexusTaskEpisodeStore(url: conversation.episodeURL)
        let checkpoint = folder.appendingPathComponent("chat.agent.json")
        try conversation.save([ChatMessage(role: "user", content: "读取report.md")])
        try Data("checkpoint".utf8).write(to: checkpoint)
        try episodes.record(goal: "读取report.md", card: card(), traces: [trace()])
        XCTAssertEqual(try episodes.load().count, 1)
        try conversation.clear(checkpointURL: checkpoint)
        XCTAssertTrue(try NexusTaskEpisodeStore(url: conversation.episodeURL).load().isEmpty)
        XCTAssertTrue(try NexusConversationStore(url: conversation.url).load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpoint.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: conversation.clearIntentURL.path))
    }

    func testPendingClearAfterRestartRemovesEpisodeBeforeClearingIntent() async throws {
        let conversation = NexusConversationStore(url: folder.appendingPathComponent("chat.json"))
        let episodes = NexusTaskEpisodeStore(url: conversation.episodeURL)
        let checkpoint = folder.appendingPathComponent("chat.agent.json")
        try episodes.record(goal: "读取report.md", card: card(), traces: [trace()])
        try Data("clear-v1".utf8).write(to: conversation.clearIntentURL)
        XCTAssertTrue(try conversation.finishPendingClear(checkpointURL: checkpoint))
        XCTAssertTrue(try episodes.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: conversation.clearIntentURL.path))
    }

    func testRecentChitchatCannotDisplaceActualFileObject() async throws {
        try Data("report".utf8).write(to: folder.appendingPathComponent("report.md"))
        let reference = ChatMessage(role: "user", content: "上一份是 /workspace/report.md")
        let chitchat = ChatMessage(role: "user", content: "你好，今天聊得开心")
        let objects = NexusTaskRecall.conversationObjects(in: [reference, chitchat])
        XCTAssertEqual(objects.map(\.title), ["report.md"])
        XCTAssertEqual(objects.first?.objectPath, "/workspace/report.md")
        XCTAssertEqual(objects.first?.observedAt, reference.createdAt)
        let candidates = try NexusTaskRecall.candidates(goal: "看看那个", memories: [], knowledge: [], skills: [],
            history: [reference, chitchat], episodes: [], workspaceRoot: folder)
        let compiled = NexusIntentCompiler.compile(goal: "看看那个", candidates: candidates, availableTools: ["workspace_read", "memory_search"])
        XCTAssertTrue(compiled.isReady)
        XCTAssertEqual(compiled.objectPath, "/workspace/report.md")
        XCTAssertEqual(compiled.preferredTool, "workspace_read")
        XCTAssertFalse(candidates.contains { $0.title.contains("你好") })
    }

    func testRecentObjectsRejectAssistantInferencesOutsidePathsAndPathSuffixes() async {
        let history = [
            ChatMessage(role: "assistant", content: "猜测对象是 /workspace/invented.md"),
            ChatMessage(role: "user", content: "你好"),
            ChatMessage(role: "user", content: "不要使用 /etc/private.txt、../../secret.md、https://example.com/docs/web.md、a.csv/../escape.md")
        ]
        XCTAssertTrue(NexusTaskRecall.conversationObjects(in: history).isEmpty)
        let explicit = ChatMessage(role: "user", content: "文件是 reports/金边预算.csv；还有 /workspace/summary.md")
        XCTAssertEqual(Set(NexusTaskRecall.conversationObjects(in: [explicit]).compactMap(\.objectPath)),
            ["/workspace/reports/金边预算.csv", "/workspace/summary.md"])
    }

    func testVagueEpisodesRecallVerifiedObjectNameOverMoreRecentDifferentObject() async throws {
        let report = NexusRecallCandidate(id: "file:phnom-penh", source: .workspaceFile, title: "金边报告",
            text: "工作区文件名", objectPath: "/workspace/reports/phnom-penh.md", provenance: "工作区目录")
        let budget = NexusRecallCandidate(id: "file:budget", source: .workspaceFile, title: "预算",
            text: "工作区文件名", objectPath: "/workspace/reports/budget.md", provenance: "工作区目录")
        for object in [report, budget] {
            let selected = NexusIntentCompiler.compile(goal: "弄一下那个", candidates: [object], availableTools: ["workspace_read"])
            XCTAssertTrue(selected.isReady)
            XCTAssertEqual(selected.objectTitle, object.title)
            try store.record(goal: "弄一下那个", card: selected,
                traces: [trace(output: "模型生成偏好：用户喜欢高风险投资", path: object.objectPath)])
        }
        let reloaded = try store.load()
        XCTAssertEqual(reloaded.map(\.goal), ["弄一下那个", "弄一下那个"])
        XCTAssertEqual(reloaded.map(\.objectTitle), ["金边报告", "预算"])
        XCTAssertLessThan(reloaded[0].observedAt, reloaded[1].observedAt)
        XCTAssertTrue(reloaded[0].candidate.aliases.contains("金边报告"))
        XCTAssertTrue(reloaded[0].candidate.aliases.contains("phnom-penh.md"))
        XCTAssertTrue(reloaded.allSatisfy { !$0.candidate.text.contains("高风险投资") && !$0.candidate.aliases.contains("高风险投资") })
        let query = "读取上次金边报告"
        let recalled = try NexusTaskRecall.candidates(goal: query, memories: [], knowledge: [], skills: [], history: [],
            episodes: reloaded, workspaceRoot: nil)
        let compiled = NexusIntentCompiler.compile(goal: query, candidates: recalled, availableTools: ["workspace_read"])
        XCTAssertTrue(compiled.isReady)
        XCTAssertEqual(compiled.objectPath, "/workspace/reports/phnom-penh.md")
        XCTAssertEqual(compiled.preferredTool, "workspace_read")
        XCTAssertTrue(NexusRecallIndex(candidates: reloaded.map(\.candidate), embedding: nil).recall(query: "高风险投资").isEmpty)
    }

    func testLegacyEpisodeWithoutObjectTitleReloadsWithoutInventingAName() async throws {
        try store.record(goal: "弄一下那个", card: card(), traces: [trace()])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [[String: Any]])
        legacy[0].removeValue(forKey: "objectTitle")
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacy)
        try legacyBytes.write(to: store.url)
        let reloaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(reloaded.goal, "弄一下那个")
        XCTAssertNil(reloaded.objectTitle)
        XCTAssertEqual(reloaded.candidate.title, "弄一下那个")
        XCTAssertEqual(reloaded.candidate.objectPath, "/workspace/report.md")
        XCTAssertFalse(reloaded.candidate.aliases.contains("金边报告"))
        XCTAssertEqual(try Data(contentsOf: store.url), legacyBytes)
    }
}
