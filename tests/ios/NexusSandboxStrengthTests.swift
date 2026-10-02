import XCTest
@testable import BlackGod

final class NexusSandboxStrengthTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testWorkspaceQuotaRejectsOversizeAndTooManyFiles() throws {
        try NexusWorkspaceQuota.enforce(adding: 1024, creatingFile: true, at: folder)
        XCTAssertThrowsError(try NexusWorkspaceQuota.enforce(adding: NexusWorkspaceQuota.maxSingleWrite + 1, creatingFile: true, at: folder))

        for i in 0..<NexusWorkspaceQuota.maxFiles {
            try Data("x".utf8).write(to: folder.appendingPathComponent("f\(i).txt"))
        }
        let snap = try NexusWorkspaceQuota.measure(at: folder)
        XCTAssertEqual(snap.files, NexusWorkspaceQuota.maxFiles)
        XCTAssertTrue(snap.exhausted)
        XCTAssertThrowsError(try NexusWorkspaceQuota.enforce(adding: 1, creatingFile: true, at: folder))
    }

    func testHTTPFetchRequiresHTTPS() async {
        let tool = NexusHTTPFetchTool(workspace: UUID(), isEnabled: { true })
        let bad = await tool.execute(NexusToolCall(id: UUID(), name: "http_fetch", arguments: [
            "url": "http://example.com", "path": "a.html"
        ]))
        XCTAssertFalse(bad.succeeded)
        XCTAssertTrue(bad.output.contains("https"))
    }

    func testNetworkToggleBlocksFetch() async {
        let tool = NexusHTTPFetchTool(workspace: UUID(), isEnabled: { true }, networkAllowed: { false })
        let result = await tool.execute(NexusToolCall(id: UUID(), name: "http_fetch", arguments: [
            "url": "https://example.com", "path": "a.html"
        ]))
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.output.contains("联网已关闭"))
    }

    func testNativeDefinitionsIncludeSandboxTools() {
        var registry = NexusToolRegistry()
        registry.register(NexusLinuxTool(workspace: UUID()))
        registry.register(NexusWorkspaceListTool(workspace: UUID()))
        registry.register(NexusWorkspaceReadTool(workspace: UUID()))
        registry.register(NexusWorkspaceWriteTool(workspace: UUID()))
        registry.register(NexusHTTPFetchTool(workspace: UUID()))
        let names = Set(registry.nativeDefinitions.map(\.name))
        XCTAssertTrue(names.contains("workspace_list"))
        XCTAssertTrue(names.contains("workspace_read"))
        XCTAssertTrue(names.contains("workspace_write"))
        XCTAssertTrue(names.contains("http_fetch"))
        XCTAssertTrue(names.contains("shell_execute"))
    }
}
