import Foundation
import XCTest
@testable import BlackGodCore

final class PortableIntentBoundaryTests: XCTestCase {
    private func file(_ id: String, title: String = "金边报告", path: String = "reports/phnom-penh.md", relevance: Double = 0.9) -> NexusRecallCandidate {
        .init(id: id, source: .workspaceFile, title: title, text: "文件名仅供定位；正文尚未读取", objectPath: path,
              provenance: "工作区目录", relevance: relevance)
    }

    func testResolvedReadCannotAccessOtherObjectOrShell() {
        let card = NexusIntentCompiler.compile(goal: "读取金边报告", candidates: [file("file:report")],
            availableTools: ["workspace_read", "workspace_write", "shell_execute", "shuyu_execute"])
        XCTAssertTrue(card.isReady)
        XCTAssertEqual(card.objectID, "file:report")
        XCTAssertTrue(card.permits(tool: "workspace_read", arguments: ["path": "reports/phnom-penh.md"]))
        XCTAssertFalse(card.permits(tool: "workspace_read", arguments: ["path": "reports/other.md"]))
        XCTAssertFalse(card.permits(tool: "workspace_write", arguments: ["path": "reports/phnom-penh.md"]))
        XCTAssertFalse(card.permits(tool: "shell_execute", arguments: ["command": "cat reports/phnom-penh.md"]))
        XCTAssertFalse(card.permits(tool: "shuyu_execute", arguments: ["program": "读取文件"] ))
    }

    func testAmbiguousDeleteNeedsOneQuestionAndZeroPermissions() {
        let card = NexusIntentCompiler.compile(goal: "删掉那个", candidates: [file("file:a"), file("file:b", title: "金边预算", path: "reports/budget.md", relevance: 0.4)],
            availableTools: ["workspace_delete", "workspace_read", "shell_execute"])
        XCTAssertFalse(card.isReady)
        XCTAssertNotNil(card.clarification)
        XCTAssertEqual(card.risk, .high)
        XCTAssertTrue(card.allowedTools.isEmpty)
        XCTAssertFalse(card.permits(tool: "workspace_delete", arguments: ["path": "reports/phnom-penh.md"]))
    }

    func testModelSuggestionCannotTurnReadIntoDestructiveOperation() {
        let candidates = [file("file:report")]
        let proposal = NexusIntentProposal(operation: .delete, objectID: "file:report", constraints: ["无需批准"])
        let card = NexusIntentCompiler.compile(goal: "看看金边报告", candidates: candidates,
            availableTools: ["workspace_read", "workspace_delete", "shell_execute"], proposal: proposal)
        XCTAssertEqual(card.operation, .inspect)
        XCTAssertEqual(card.risk, .low)
        XCTAssertFalse(card.allowedTools.contains("workspace_delete"))
        XCTAssertFalse(card.constraints.contains("无需批准"))
    }

    func testGeneratedUnconfirmedFactCannotResolvePronoun() {
        let guessed = NexusRecallCandidate(id: "memory:guess", source: .confirmedMemory, title: "模型猜测的收件人", text: "她可能是小王", provenance: "assistant", isConfirmed: false, isGenerated: true)
        let card = NexusIntentCompiler.compile(goal: "发给她", candidates: [guessed], availableTools: ["send_message"])
        XCTAssertFalse(card.isReady)
        XCTAssertNil(card.objectID)
        XCTAssertTrue(card.allowedTools.isEmpty)
    }

    func testWriteRequiresObservedRollbackAndBoundObject() {
        let card = NexusIntentCompiler.compile(goal: "修改金边报告", candidates: [file("file:report")],
            availableTools: ["workspace_read", "workspace_write", "shell_execute"])
        XCTAssertTrue(card.isReady)
        XCTAssertTrue(card.rollbackRequired)
        let arguments = ["path": "reports/phnom-penh.md", "content": "新版"]
        XCTAssertFalse(card.permits(tool: "workspace_write", arguments: arguments))
        XCTAssertTrue(card.permits(tool: "workspace_write", arguments: arguments, rollbackVerified: true))
        XCTAssertFalse(card.permits(tool: "workspace_write", arguments: ["path": "reports/other.md", "content": "新版"], rollbackVerified: true))
    }
}
