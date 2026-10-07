import Foundation
import XCTest
@testable import BlackGod

final class NexusRecallTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func memory(_ id: String, title: String, text: String, date: Date? = nil,
                        confirmed: Bool = true, generated: Bool = false) -> NexusRecallCandidate {
        NexusRecallCandidate(id: id, source: .confirmedMemory, title: title, text: text,
            observedAt: date ?? now, provenance: "用户在记忆编辑器确认", isConfirmed: confirmed, isGenerated: generated)
    }

    func testSemanticRecallFindsSynonymWithoutLexicalOverlapUsingInjectedLocalEmbedding() {
        let embedding = NexusLocalEmbedding(name: "回归用本地语义向量") { text in
            if text.contains("财务") || text.contains("开销") { return [1, 0, 0] }
            return [0, 1, 0]
        }
        let index = NexusRecallIndex(candidates: [
            memory("memory:budget", title: "财务", text: "支出凭证"),
            memory("memory:music", title: "音乐", text: "乐器曲谱")
        ], embedding: embedding)
        XCTAssertTrue(NexusRecallIndex.terms("财务 支出凭证").intersection(NexusRecallIndex.terms("开销")).isEmpty)
        let result = index.recall(query: "开销", now: now)
        XCTAssertEqual(result.map(\.evidenceID), ["memory:budget"])
        XCTAssertEqual(result.first?.retrievalMethod, .localSemantic)
    }

    func testLexicalFallbackIsExplicitAndNeverPretendsToUnderstandSynonyms() {
        let index = NexusRecallIndex(candidates: [memory("m", title: "财务", text: "支出凭证")], embedding: nil)
        XCTAssertEqual(index.recall(query: "财务", now: now).first?.retrievalMethod, .lexical)
        XCTAssertTrue(index.recall(query: "开销", now: now).isEmpty)
        XCTAssertTrue(index.backendName.contains("不可用"))
    }

    func testOnlyConfirmedMemoryAndEvidenceBackedObservationsEnterIndex() {
        let observed = NexusRecallCandidate(id: "task:observed", source: .taskSummary, title: "账单", text: "read_file观测",
            observedAt: now, provenance: "任务输出", evidencePointers: ["tool:read-1"])
        let inferred = NexusRecallCandidate(id: "task:guess", source: .taskSummary, title: "账单推断", text: "她喜欢高风险投资",
            observedAt: now, provenance: "模型摘要", evidencePointers: ["tool:read-1"], isGenerated: true)
        let unsupported = NexusRecallCandidate(id: "task:none", source: .taskSummary, title: "账单空证据", text: "无输出",
            observedAt: now, provenance: "模型摘要")
        let index = NexusRecallIndex(candidates: [
            memory("memory:confirmed", title: "账单名称", text: "金边预算"),
            memory("memory:pending", title: "账单候选", text: "未确认", confirmed: false),
            memory("memory:generated", title: "账单猜测", text: "生成偏好", generated: true),
            observed, inferred, unsupported
        ], embedding: nil)
        XCTAssertEqual(Set(index.indexedCandidates.map(\.id)), ["memory:confirmed", "task:observed"])
        XCTAssertEqual(Set(index.recall(query: "账单", now: now).map(\.id)), ["memory:confirmed", "task:observed"])
    }

    func testRecentConversationAndSkillAreContextOnlyAndNeverPersistedInVectorIndex() {
        let recent = NexusRecallCandidate(id: "message:1", source: .recentConversation, title: "金边预算", text: "用户正在处理的文件",
            objectPath: "/workspace/phnom-penh.csv", observedAt: now, provenance: "近期用户原话", aliases: ["金边那份"])
        let skill = NexusRecallCandidate(id: "skill:1", source: .skill, title: "账单检查", text: "读取并核对账单",
            observedAt: now, provenance: "已保存技能")
        let generated = NexusRecallCandidate(id: "message:generated", source: .recentConversation, title: "金边推断", text: "她的隐含偏好",
            observedAt: now, provenance: "模型回复", isGenerated: true)
        let index = NexusRecallIndex(candidates: [recent, skill], embedding: nil)
        XCTAssertTrue(index.indexedCandidates.isEmpty)
        XCTAssertEqual(index.recall(query: "金边那份", now: now, supplemental: [recent, skill, generated]).map(\.id), ["message:1"])
        XCTAssertTrue(index.indexedCandidates.isEmpty)
    }

    func testExpirationWithdrawalAndReplacementRemoveOldEvidence() {
        let expired = NexusRecallCandidate(id: "memory:expired", source: .confirmedMemory, title: "语言", text: "英文",
            observedAt: now, provenance: "用户确认", isConfirmed: true, expiresAt: now.addingTimeInterval(-1))
        let index = NexusRecallIndex(candidates: [expired, memory("memory:active", title: "语言", text: "中文")], embedding: nil)
        XCTAssertEqual(index.recall(query: "语言", now: now).map(\.id), ["memory:active"])
        index.remove(evidenceID: "memory:active")
        XCTAssertTrue(index.recall(query: "语言", now: now).isEmpty)
        index.upsert(memory("memory:active", title: "语言", text: "法语"))
        index.replace(with: [])
        XCTAssertTrue(index.recall(query: "语言", now: now).isEmpty)
    }

    func testNewestWithdrawnCandidateCannotReviveOlderFactWithSameIdentity() {
        let old = memory("memory:1", title: "语言", text: "英文", date: now.addingTimeInterval(-1))
        let withdrawn = memory("memory:1", title: "语言", text: "未确认修订", confirmed: false)
        let index = NexusRecallIndex(candidates: [old, withdrawn], embedding: nil)
        XCTAssertTrue(index.indexedCandidates.isEmpty)
        XCTAssertTrue(index.recall(query: "语言", now: now).isEmpty)
    }

    func testDemonstrativeQueryUsesVisibleRecencyPriorWithoutClaimingSemanticHit() {
        let index = NexusRecallIndex(candidates: [
            memory("memory:older", title: "旧报告", text: "旧文件", date: now.addingTimeInterval(-86400)),
            memory("memory:latest", title: "金边预算", text: "新文件")
        ], embedding: nil)
        let hits = index.recall(query: "弄一下那个", now: now)
        XCTAssertEqual(hits.map(\.id), ["memory:latest", "memory:older"])
        XCTAssertTrue(hits.allSatisfy { $0.retrievalMethod == .recency && $0.relevance <= 0.15 })
    }

    func testInvalidAndDifferentVectorSpacesFallBackToLexicalEvidence() {
        let invalid = NexusLocalEmbedding(name: "无效向量", vector: { _ in [Double.nan, 0] })
        let candidate = memory("m", title: "财务", text: "支出")
        XCTAssertEqual(NexusRecallIndex(candidates: [candidate], embedding: invalid).recall(query: "财务", now: now).first?.retrievalMethod, .lexical)
        let separated = NexusLocalEmbedding(name: "中文句向量与词均值独立空间",
            space: { $0.contains("开销") ? "zh-Hans-word-mean" : "zh-Hans-sentence" }, vector: { _ in [1, 0] })
        XCTAssertTrue(NexusRecallIndex(candidates: [candidate], embedding: separated).recall(query: "开销", now: now).isEmpty)
    }

    func testStableEvidenceIDsAndProvenanceSurviveCodableRoundTripAndRanking() throws {
        let candidate = memory("memory:stable-id", title: "语言", text: "中文")
        let restored = try JSONDecoder().decode(NexusRecallCandidate.self, from: JSONEncoder().encode(candidate))
        let ranked = NexusRecallIndex(candidates: [restored], embedding: nil).recall(query: "语言", now: now)
        XCTAssertEqual(ranked.first?.evidenceID, candidate.evidenceID)
        XCTAssertEqual(ranked.first?.provenance, candidate.provenance)
        XCTAssertEqual(ranked.first?.observedAt, now)
        XCTAssertTrue(NexusRecallIndex.evidenceContext(ranked).contains("memory:stable-id"))
    }

    func testWorkspaceIndexStoresNamesOnlyAndDiscardsAccidentallyProvidedBody() {
        let candidate = NexusRecallCandidate(id: "file:1", source: .workspaceFile, title: "report.txt", text: "绝不能进入索引的正文密钥",
            objectPath: "/workspace/report.txt", observedAt: now, provenance: "工作区目录")
        let index = NexusRecallIndex(candidates: [candidate], embedding: nil)
        XCTAssertEqual(index.indexedCandidates.first?.text, "/workspace/report.txt")
        XCTAssertTrue(index.recall(query: "正文密钥", now: now).isEmpty)
        XCTAssertEqual(index.recall(query: "report.txt", now: now).first?.objectPath, "/workspace/report.txt")
    }

    func testWorkspaceNameScanDoesNotReadFileBodyOrFollowSymlinkAndValidatesCurrentPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("reports"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try Data("secret body is never indexed".utf8).write(to: root.appendingPathComponent("reports/金边预算.txt"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden"))
        try Data("outside".utf8).write(to: outside.appendingPathComponent("private.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.txt"), withDestinationURL: outside.appendingPathComponent("private.txt"))
        let first = try NexusRecallIndex.workspaceFileNames(root: root)
        let second = try NexusRecallIndex.workspaceFileNames(root: root)
        XCTAssertEqual(first.map(\.evidenceID), second.map(\.evidenceID))
        XCTAssertEqual(first.map(\.objectPath), ["/workspace/reports/金边预算.txt"])
        XCTAssertFalse(first.map(\.text).joined().contains("secret"))
        let candidate = try XCTUnwrap(first.first)
        XCTAssertTrue(NexusRecallIndex.validateWorkspaceObject(candidate, root: root))
        try FileManager.default.removeItem(at: root.appendingPathComponent("reports/金边预算.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("reports/金边预算.txt"), withDestinationURL: outside.appendingPathComponent("private.txt"))
        XCTAssertFalse(NexusRecallIndex.validateWorkspaceObject(candidate, root: root))
    }

    func testPathTraversalAndSymlinkRootCannotBecomeWorkspaceCandidates() throws {
        for path in ["/etc/passwd", "/workspace/../private.txt", "../private.txt", "/workspace/a//b", "/workspace/a/./b"] {
            let candidate = NexusRecallCandidate(id: path, source: .workspaceFile, title: "private", text: "", objectPath: path, provenance: "目录项")
            XCTAssertFalse(candidate.isIndexable, path)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let link = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        defer { try? FileManager.default.removeItem(at: link); try? FileManager.default.removeItem(at: folder) }
        XCTAssertThrowsError(try NexusRecallIndex.workspaceFileNames(root: link))
    }

    func testWorkspaceScanAndRecallRespectBounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("a.txt"))
        try Data().write(to: root.appendingPathComponent("b.txt"))
        try Data().write(to: root.appendingPathComponent("nested/c.txt"))
        XCTAssertEqual(try NexusRecallIndex.workspaceFileNames(root: root, maximumFiles: 1).count, 1)
        XCTAssertEqual(try NexusRecallIndex.workspaceFileNames(root: root, maximumDepth: 0).count, 2)
        let index = NexusRecallIndex(candidates: [memory("b", title: "报告", text: "B"), memory("a", title: "报告", text: "A")], embedding: nil)
        XCTAssertEqual(index.recall(query: "报告", limit: 1, now: now).map(\.id), ["a"])
        XCTAssertTrue(index.recall(query: "报告", limit: 0, now: now).isEmpty)
        XCTAssertTrue(index.recall(query: "  ", now: now).isEmpty)
    }
}
