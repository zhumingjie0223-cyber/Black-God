import XCTest
@testable import BlackGod

@MainActor
final class NexusRetrievalEvidenceTests: XCTestCase {
    private func record(_ tool: String, output: String, succeeded: Bool = true) -> NexusEvidenceRecord {
        NexusEvidenceRecord(id: NexusEvidenceAudit.toolID(UUID()), stepID: UUID(), tool: tool,
            succeeded: succeeded, output: output)
    }

    private func audit(_ tool: String, output: String, answer: String) -> NexusEvidenceAuditReport {
        NexusEvidenceAudit.review(answer: answer, records: [record(tool, output: output)],
            requirements: [NexusEvidenceRequirement(id: "retrieve", description: "取得匹配资料", toolName: tool)])
    }

    func testCompletedEmptyMemorySearchCannotVerifyInventedPreference() async throws {
        let result = await NexusMemorySearchTool(items: []).execute(
            NexusToolCall(id: UUID(), name: "memory_search", arguments: ["query": "投资偏好"]))
        XCTAssertTrue(result.succeeded, "查询正常结束不等于召回到资料")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        XCTAssertEqual(object["status"] as? String, "no_matches")
        XCTAssertEqual(object["count"] as? Int, 0)
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "memory_search", output: result.output), .empty)
        XCTAssertTrue(NexusEvidence.sourceReferences(in: result.output).isEmpty)
        let reviewed = audit("memory_search", output: result.output, answer: "你喜欢高风险投资。")
        XCTAssertFalse(reviewed.passed)
        XCTAssertTrue(reviewed.issues.contains { $0.contains("未取得可引用") })
    }

    func testHonestNoMatchAnswerDoesNotPretendRelevantFactsWereRetrieved() async {
        let answer = NexusEvidenceAudit.emptyRetrievalMessage(tool: "memory_search")!
        let reviewed = audit("memory_search", output: "没有检索到相关用户记录，不要编造记忆。", answer: answer)
        XCTAssertTrue(reviewed.slotsComplete)
        XCTAssertTrue(reviewed.authorized)
        XCTAssertFalse(reviewed.evidenceConsistent)
        XCTAssertFalse(reviewed.passed)
        XCTAssertFalse(answer.contains("你喜欢"))
    }

    func testZeroMatchesRemainUnsupportedWhenModelAddsAnAbstentionBeforeAGuess() async {
        let reviewed = audit("memory_search", output: "没有检索到相关用户记录，不要编造记忆。",
            answer: "没有查到相关用户记录。不过你应该喜欢高风险投资，我已经完成偏好核对。")
        XCTAssertFalse(reviewed.passed)
        XCTAssertTrue(reviewed.issues.contains { $0.contains("未取得可引用") })
    }

    func testAssistantGeneratedMemoriesNeverProduceRetrievedUserFacts() async {
        var guess = NexusMemoryItem(id: UUID(), text: "喜欢高风险投资", kind: "preference", source: "assistant",
            confidence: 1, createdAt: Date(), expiresAt: nil)
        guess.label = "投资偏好"
        let result = await NexusMemorySearchTool(items: [guess]).execute(
            NexusToolCall(id: UUID(), name: "memory_search", arguments: ["query": "投资偏好"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "memory_search", output: result.output), .empty)
        XCTAssertFalse(result.output.contains(guess.text))
    }

    func testConfirmedMemoryRetainsExistingCandidateProtocolAndSourcePointers() async {
        var item = NexusMemoryItem(id: UUID(), text: "仅接受低风险投资", kind: "preference", source: "user",
            confidence: 1, createdAt: Date(), expiresAt: nil)
        item.label = "投资偏好"
        let result = await NexusMemorySearchTool(items: [item]).execute(
            NexusToolCall(id: UUID(), name: "memory_search", arguments: ["query": "投资偏好"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.contains(item.text))
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "memory_search", output: result.output), .matched)
        let references = NexusEvidence.sourceReferences(in: result.output)
        XCTAssertEqual(references.map(\.id), ["memory:" + item.id.uuidString.lowercased()])
        XCTAssertTrue(references[0].verified, "仅确认这条记录由用户保存，不独立认证记录内容")
        XCTAssertTrue(audit("memory_search", output: result.output,
            answer: "用户保存的投资偏好记录是：仅接受低风险投资。该陈述未独立核实。").passed)
    }

    func testArbitraryRetrievalTextCannotSatisfyAResultRequirement() async {
        for tool in ["memory_search", "skill_search", "web_lookup"] {
            let output = "你喜欢高风险投资，已查到。"
            XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: tool, output: output), .invalid)
            XCTAssertFalse(audit(tool, output: output, answer: output).passed)
        }
    }

    func testUnconfirmedGeneratedAndEmptyMemoryCandidatesAreNotEvidence() async throws {
        let id = "memory:" + UUID().uuidString.lowercased()
        let valid: [String: Any] = ["id": id, "source": "confirmedMemory", "isConfirmed": true,
            "isGenerated": false, "text": "仅接受低风险投资"]
        for replacement in [["isConfirmed": false], ["isGenerated": true], ["text": "  "], ["id": "memory:not-an-id"]] as [[String: Any]] {
            var candidate = valid
            candidate.merge(replacement) { _, next in next }
            let data = try JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys])
            let output = String(decoding: data, as: UTF8.self)
            XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "memory_search", output: output), .invalid)
            XCTAssertFalse(audit("memory_search", output: output, answer: "你喜欢高风险投资。").passed)
        }
    }

    func testUnrelatedCalculationCannotReplaceAnEmptyRetrievalRequirement() async {
        let reviewed = NexusEvidenceAudit.review(answer: "36，你喜欢高风险投资。", records: [
            record("memory_search", output: "没有检索到相关用户记录，不要编造记忆。"),
            record("calc", output: "36")], requirements: [
                NexusEvidenceRequirement(id: "preference", description: "取得用户偏好记录", toolName: "memory_search")])
        XCTAssertFalse(reviewed.passed)
        XCTAssertTrue(reviewed.issues.contains { $0.contains("条件「取得用户偏好记录」") })
    }

    func testRecentObjectPriorAloneCannotProveARelevantUserFact() async {
        let id = "memory:" + UUID().uuidString.lowercased()
        let candidate = NexusRecallCandidate(id: id, source: .confirmedMemory, title: "项目名称", text: "Black God",
            isConfirmed: true, evidencePointers: [id], retrievalMethod: .recency)
        let output = NexusRecallIndex.evidenceContext([candidate])
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "memory_search", output: output), .empty)
        XCTAssertFalse(audit("memory_search", output: output, answer: "上次她喜欢高风险投资。").passed)
    }

    func testRealMemoryToolDoesNotPromoteUnmatchedSheOrPreviousReferencesToFacts() async {
        var item = NexusMemoryItem(id: UUID(), text: "Black God", kind: "fact", source: "user",
            confidence: 1, createdAt: Date(), expiresAt: nil)
        item.label = "项目名称"
        // 同一真实查询分别覆盖无向量后端、存在后端但向量未命中的情况。
        let orthogonal = NexusLocalEmbedding(name: "回归用本地向量") { text in
            text.contains("项目名称") ? [1, 0] : [0, 1]
        }
        for embedding in [nil, orthogonal] as [NexusLocalEmbedding?] {
            for query in ["她的投资偏好", "上次的风险喜好"] {
                let candidates = NexusMemoryRetrieval.candidates([item])
                let prior = NexusRecallIndex(candidates: candidates, embedding: embedding).recall(query: query)
                XCTAssertEqual(prior.first?.retrievalMethod, .recency, "编译器仍可取得消歧先验")
                let result = await NexusMemorySearchTool(items: [item], embedding: embedding).execute(
                    NexusToolCall(id: UUID(), name: "memory_search", arguments: ["query": query]))
                XCTAssertTrue(result.succeeded)
                XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "memory_search", output: result.output), .empty)
                XCTAssertFalse(result.output.contains(item.text))
                XCTAssertFalse(audit("memory_search", output: result.output, answer: "她喜欢高风险投资。").passed)
            }
        }
    }

    func testRealSkillSearchDistinguishesEmptyAndExistingDirectoryRows() async {
        let query = NexusToolCall(id: UUID(), name: "skill_search", arguments: ["query": "订单核对"])
        let empty = await NexusSkillSearchTool(items: []).execute(query)
        XCTAssertTrue(empty.succeeded)
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "skill_search", output: empty.output), .empty)
        XCTAssertFalse(audit("skill_search", output: empty.output, answer: "已找到订单流程。").passed)
        let content = NexusSkillContent(name: "订单核对", applicability: "订单包含单价与数量", steps: "核对总价", verification: "比较原订单")
        let skill = NexusSkill(id: UUID(), current: NexusSkillRevision(id: UUID(), number: 1, content: content, savedAt: Date()),
            history: [], sourceTaskID: nil, sourceEvidenceIDs: [])
        let found = await NexusSkillSearchTool(items: [skill]).execute(query)
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "skill_search", output: found.output), .matched)
        XCTAssertTrue(audit("skill_search", output: found.output, answer: "目录中找到订单核对流程，尚未执行。").passed)
    }

    func testSuccessfulPublicDocumentFetchWithoutMatchingSnippetIsNotRelevantEvidence() async {
        let url = URL(string: "https://example.com/report")!
        let tool = NexusReadOnlyLookupTool(networkAllowed: { true }, isAuthorizedURL: { $0 == url }, transport: { request, _ in
            NexusLookupResponse(data: Data("公开报告，未包含投资偏好".utf8), url: request.url!, statusCode: 200, mimeType: "text/plain")
        })
        let result = await tool.execute(NexusToolCall(id: UUID(), name: "web_lookup",
            arguments: ["url": url.absoluteString, "query": "高风险投资"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "web_lookup", output: result.output), .empty)
        XCTAssertFalse(audit("web_lookup", output: result.output, answer: "页面已证实你喜欢高风险投资。").passed)
    }

    func testPublicDocumentWithMatchedSnippetRemainsUnverifiedExternalEvidence() async {
        let url = URL(string: "https://example.com/report")!
        let tool = NexusReadOnlyLookupTool(networkAllowed: { true }, isAuthorizedURL: { $0 == url }, transport: { request, _ in
            NexusLookupResponse(data: Data("公开报告：预算12。".utf8), url: request.url!, statusCode: 200, mimeType: "text/plain")
        })
        let result = await tool.execute(NexusToolCall(id: UUID(), name: "web_lookup",
            arguments: ["url": url.absoluteString, "query": "预算"]))
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "web_lookup", output: result.output), .matched)
        XCTAssertEqual(NexusEvidence.sourceReferences(in: result.output).first?.verified, false)
        XCTAssertTrue(audit("web_lookup", output: result.output, answer: "页面声称预算12；外部内容尚未独立核验。").passed)
    }

    func testBlankDocumentExtractAndContradictoryMatchFlagsDoNotProduceEvidence() async throws {
        let source = "https://example.com/report"
        let base: [String: Any] = ["sourceID": "url:" + source, "sourceURL": source, "matched": true, "snippets": ["   "]]
        let blank = String(decoding: try JSONSerialization.data(withJSONObject: base), as: UTF8.self)
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "web_lookup", output: blank), .empty)
        var contradictory = base
        contradictory["matched"] = false
        contradictory["snippets"] = ["预算12"]
        let output = String(decoding: try JSONSerialization.data(withJSONObject: contradictory), as: UTF8.self)
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "web_lookup", output: output), .invalid)
        XCTAssertFalse(audit("web_lookup", output: output, answer: "已核对预算12。").passed)
    }

    func testRetrievalRequirementCannotReferToAnotherCallsMatchedEvidence() async {
        let empty = record("memory_search", output: "没有检索到相关用户记录，不要编造记忆。")
        let matched = record("skill_search", output: "当前技能目录（共1项）：\nID=\(UUID())，版本=1，名称=订单核对")
        let requirement = NexusEvidenceRequirement(id: "scope", description: "当前检索须有资料", toolName: "memory_search", evidenceIDs: [empty.id])
        XCTAssertFalse(NexusEvidenceAudit.review(answer: "已核对用户偏好。", records: [empty, matched], requirements: [requirement]).passed)
    }

    func testNonRetrievalToolsKeepExistingSuccessSemantics() async {
        XCTAssertEqual(NexusEvidenceAudit.retrievalStatus(tool: "calc", output: "36"), .notRetrieval)
        XCTAssertNil(NexusEvidenceAudit.emptyRetrievalMessage(tool: "calc"))
        let reviewed = NexusEvidenceAudit.review(answer: "结果36。", records: [record("calc", output: "36")], requirements: [
            NexusEvidenceRequirement(id: "sum", description: "计算总价", toolName: "calc", expectedOutput: "36")])
        XCTAssertTrue(reviewed.passed)
    }
}
