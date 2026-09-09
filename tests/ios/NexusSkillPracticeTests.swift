import XCTest
@testable import BlackGod

private struct SlowPracticeTool: NexusTool {
    let name = "calc"
    let entered: () -> Void
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        entered()
        try? await Task.sleep(for: .seconds(20))
        return NexusToolResult(callID: call.id, output: "36", succeeded: true)
    }
}

@MainActor
final class NexusSkillPracticeTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws { folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private var url: URL { folder.appendingPathComponent("practice.json") }
    private func tools() -> NexusToolRegistry {
        var tools = NexusToolRegistry(); tools.register(NexusCalculatorTool()); tools.register(NexusShuyuTool())
        tools.register(NexusLinuxTool(workspace: NexusWorkspaceIdentity.id(for: "tests-practice"), isEnabled: { true }))
        return tools
    }
    func testMigratedLibraryNeverPretendsMissingAudioToolExists() {
        XCTAssertEqual(NexusBuiltinSkills.all.count, 5)
        XCTAssertEqual(NexusBuiltinSkills.available.count, 4)
        XCTAssertTrue(NexusBuiltinSkills.all.last?.missing?.contains("转写") == true)
        let store = NexusSkillStore(url: folder.appendingPathComponent("skills.json"))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.available.count, 4)
    }
    func testThreeActualRoundsPersistAndChangedVersionDoesNotInheritPasses() async throws {
        let runner = NexusSkillPractice(url: url)
        for _ in 0..<3 { await runner.run(tools: tools()) }
        XCTAssertEqual(runner.rounds.count, 3)
        XCTAssertEqual(runner.rounds.last?.results.count, 12)
        XCTAssertTrue(runner.rounds.allSatisfy { $0.results.allSatisfy(\.passed) }, String(describing: runner.rounds.last?.results))
        let skill = NexusBuiltinSkills.all[0]
        XCTAssertEqual(runner.successfulRounds(skill), 3)
        XCTAssertEqual(NexusSkillPractice(url: url).successfulRounds(skill), 3)
        var changed = skill.skill
        changed.current = NexusSkillRevision(id: UUID(), number: 2, content: changed.current.content, savedAt: Date())
        let revised = NexusBuiltinSkill(id: skill.id, skill: changed, source: skill.source, missing: nil, cases: skill.cases)
        XCTAssertEqual(runner.successfulRounds(revised), 0)
    }
    func testFailedLatestRoundBreaksPreviousPassingStreak() async {
        let runner = NexusSkillPractice(url: url)
        await runner.run(tools: tools())
        XCTAssertEqual(runner.successfulRounds(NexusBuiltinSkills.all[0]), 1)
        var missingShell = NexusToolRegistry(); missingShell.register(NexusCalculatorTool()); missingShell.register(NexusShuyuTool())
        await runner.run(tools: missingShell)
        XCTAssertEqual(runner.successfulRounds(NexusBuiltinSkills.all[0]), 0)
        XCTAssertEqual(runner.successfulRounds(NexusBuiltinSkills.all[1]), 2)
    }
    func testCorruptArchiveIsPreservedAndCannotStartAutomaticPractice() async throws {
        let corrupt = Data("invalid".utf8); try corrupt.write(to: url)
        let runner = NexusSkillPractice(url: url)
        await runner.run(tools: tools())
        XCTAssertFalse(runner.due); XCTAssertFalse(runner.isRunning)
        XCTAssertNotNil(runner.lastError); XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
    func testWriteFailurePreventsExercises() async throws {
        try Data().write(to: url)
        let runner = NexusSkillPractice(url: url.appendingPathComponent("child"))
        await runner.run(tools: tools())
        XCTAssertTrue(runner.rounds.isEmpty); XCTAssertNotNil(runner.lastError)
    }
    func testUserSkillCapacityExpandedAndDirectoryIsBounded() throws {
        let store = NexusSkillStore(url: folder.appendingPathComponent("skills.json"))
        for n in 0..<35 { try store.save(NexusSkillContent(name: "技能\(n)", applicability: "测试", steps: "计算", verification: "检查")) }
        XCTAssertEqual(store.items.count, 35)
        let index = NexusSkillRetrieval.index(store.available)
        XCTAssertTrue(index.contains("最多30项"))
        XCTAssertLessThan(index.count, 12000)
        XCTAssertFalse(NexusSkillRetrieval.search(store.items, query: "技能34").isEmpty)
    }
    func testCancellationPersistsIncompleteRoundAndDoesNotPromoteSkill() async {
        let runner = NexusSkillPractice(url: url)
        let entered = expectation(description: "演练开始")
        var registry = tools()
        registry.register(SlowPracticeTool(entered: { entered.fulfill() }))
        let task = Task { await runner.run(skills: [NexusBuiltinSkills.all[0]], tools: registry) }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel(); await task.value
        XCTAssertEqual(runner.rounds.last?.state, "cancelled")
        XCTAssertEqual(runner.live.state, .cancelled)
        XCTAssertEqual(runner.successfulRounds(NexusBuiltinSkills.all[0]), 0)
        XCTAssertFalse(runner.due)
        XCTAssertEqual(NexusSkillPractice(url: url).rounds.last?.state, "cancelled")
    }

}
