import Foundation
import XCTest
@testable import BlackGod

private actor GovernedToolCalls {
    var count = 0
    func record() { count += 1 }
}

private struct GovernedWorkspaceFixture: NexusTool {
    let name: String
    let usage = "工作区租约回归用的可观测工具"
    let calls: GovernedToolCalls
    let revoke: @MainActor () throws -> Void

    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        await calls.record()
        do {
            try await revoke()
            return .init(callID: call.id, output: "工具已返回可观测结果", succeeded: true)
        } catch {
            return .init(callID: call.id, output: error.localizedDescription, succeeded: false)
        }
    }
}

/// 使用实际治理存储验证新工具接入和到期复核，不运行客体命令。
@MainActor
final class NexusToolGovernanceIntegrationTests: XCTestCase {
    private var folder: URL!
    private var control: NexusCognitiveControl!
    private let workspaceTools = ["workspace_list", "workspace_read", "workspace_write", "workspace_delete", "workspace_restore", "http_fetch", "shell_execute"]

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        control = NexusCognitiveControl(url: folder.appendingPathComponent("governance.json"))
    }

    override func tearDown() async throws {
        try? control.allowAnalysis()
        try? FileManager.default.removeItem(at: folder)
    }

    func testEveryWorkspaceToolRequiresExplicitLiveLease() async throws {
        for name in workspaceTools {
            let call = NexusToolCall(id: UUID(), name: name, arguments: ["path": "report.md"])
            XCTAssertThrowsError(try control.begin(call), name)
        }
        try control.grantWorkspace()
        for name in workspaceTools {
            let call = NexusToolCall(id: UUID(), name: name, arguments: [:])
            let revision = try control.begin(call)
            XCTAssertNoThrow(try control.finish(call, succeeded: true, startedRevision: revision), name)
        }
        XCTAssertTrue(control.state.pendingToolCalls.isEmpty)
    }

    func testLeaseExpiryDuringToolPreventsResultDeliveryForEveryWorkspaceTool() async throws {
        let started = Date()
        try control.grantWorkspace(now: started)
        for name in workspaceTools {
            let call = NexusToolCall(id: UUID(), name: name, arguments: [:])
            let revision = try control.begin(call, now: started)
            XCTAssertThrowsError(try control.finish(call, succeeded: true, startedRevision: revision,
                now: started.addingTimeInterval(1801)), name)
            XCTAssertThrowsError(try control.begin(.init(id: UUID(), name: name, arguments: [:]),
                now: started.addingTimeInterval(1801)), name)
        }
    }

    func testReadOnlyLookupStillRunsItsOwnURLAndNetworkGuards() async throws {
        let call = NexusToolCall(id: UUID(), name: "web_lookup", arguments: ["url": "https://example.com/"])
        let revision = try control.begin(call)
        XCTAssertNoThrow(try control.finish(call, succeeded: true, startedRevision: revision))
        var tool = NexusReadOnlyLookupTool()
        tool.networkAllowed = { true }
        tool.isAuthorizedURL = { _ in false }
        var requests = 0
        tool.transport = { _, _ in requests += 1; throw URLError(.badURL) }
        var registry = NexusToolRegistry(control: control)
        registry.register(tool)
        let output = await registry.execute(call)
        XCTAssertFalse(output.succeeded)
        XCTAssertTrue(output.output.contains("未由用户明确指定"))
        XCTAssertEqual(requests, 0)
        try control.revokeAll()
        XCTAssertThrowsError(try control.begin(call))
    }

    func testUnknownToolDoesNotGainPermissionFromWorkspaceLease() async throws {
        try control.grantWorkspace()
        XCTAssertThrowsError(try control.begin(.init(id: UUID(), name: "invented_payment", arguments: [:])))
    }

    func testRegistryNeverStartsWorkspaceToolWithoutLease() async throws {
        let calls = GovernedToolCalls()
        var registry = NexusToolRegistry(control: control)
        registry.register(GovernedWorkspaceFixture(name: "workspace_write", calls: calls, revoke: {}))
        let result = await registry.execute(.init(id: UUID(), name: "workspace_write", arguments: ["path": "report.md"]))
        XCTAssertFalse(result.succeeded)
        let count = await calls.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(control.state.audit.last?.event, "tool.denied")
    }

    func testRevokedLeaseHidesResultAfterObservedExecution() async throws {
        try control.grantWorkspace()
        let calls = GovernedToolCalls()
        var registry = NexusToolRegistry(control: control)
        registry.register(GovernedWorkspaceFixture(name: "workspace_restore", calls: calls, revoke: {
            try self.control.allowAnalysis()
        }))
        let result = await registry.execute(.init(id: UUID(), name: "workspace_restore", arguments: ["path": "report.md"]))
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.output.contains("结果不再交给模型"))
        let count = await calls.count
        XCTAssertEqual(count, 1, "不能假称撤销已阻止此前生效的动作")
    }
}
