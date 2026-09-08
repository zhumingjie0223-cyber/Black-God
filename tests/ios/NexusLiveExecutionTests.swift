import XCTest
@testable import BlackGod

@MainActor
final class NexusLiveExecutionTests: XCTestCase {
    func testLiveDisplayIsBoundedRedactedAndRejectsLateOutput() {
        let live = NexusLiveExecution()
        live.begin(goal: "test secret-value", redacting: "secret-value")
        for _ in 0..<150 { live.append(.output, "secret-value " + String(repeating: "中", count: 1500)) }
        XCTAssertLessThanOrEqual(live.entries.count, 60)
        XCTAssertLessThanOrEqual(live.entries.map(\.text).reduce(0) { $0 + $1.count }, 16000)
        XCTAssertTrue(live.omitted)
        XCTAssertFalse(live.goal.contains("secret-value"))
        XCTAssertFalse(live.entries.contains { $0.text.contains("secret-value") })
        live.finish(.cancelled, message: "停止")
        let ids = live.entries.map(\.id)
        live.append(.output, "late output")
        live.phase("late phase")
        XCTAssertEqual(live.entries.map(\.id), ids)
        XCTAssertEqual(live.state, .cancelled)
        live.begin(goal: "next")
        XCTAssertTrue(live.entries.isEmpty)
        XCTAssertFalse(live.omitted)
    }
    func testCheckpointUpdatesDoNotDuplicateVisibleEvidence() {
        let live = NexusLiveExecution(); live.begin(goal: "计算")
        let trace = NexusToolTrace(stepID: UUID(), round: 1, call: NexusToolCall(id: UUID(), name: "calc", arguments: ["expression": "2+2"]), result: "4", succeeded: true, timestamp: Date())
        live.observe([trace]); live.observe([trace])
        XCTAssertEqual(live.entries.count, 1)
        XCTAssertTrue(live.entries[0].text.contains("4"))
    }
    func testFreshInstallEnablesEmbeddedExecutionButHonorsOptOut() throws {
        let suite = "blackgod.tests.execution." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(NexusLinuxTool.enabled(in: defaults))
        defaults.set(false, forKey: "blackgod.linux.modelTools")
        XCTAssertFalse(NexusLinuxTool.enabled(in: defaults))
        defaults.set(true, forKey: "blackgod.linux.modelTools")
        XCTAssertTrue(NexusLinuxTool.enabled(in: defaults))
    }
    func testActualLinuxOutputIsDeliveredBeforeProcessExit() async throws {
        let arrived = expectation(description: "streamed output")
        var output: [String] = []
        var ended = false
        let task = Task {
            defer { ended = true }
            return try await NexusLinuxRuntime.shared.execute(command: "printf 'first\\n'; sleep 2; printf 'last\\n'", workspace: UUID(), onOutput: { line, _ in
                output.append(line)
                if line == "first" { arrived.fulfill() }
            })
        }
        await fulfillment(of: [arrived], timeout: 5)
        XCTAssertFalse(ended)
        let result = try await task.value
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(output, ["first", "last"])
    }
    func testOutputFloodHasBoundedCallbacksAndPreservesFinalResult() async throws {
        var lines: [String] = []
        let result = try await NexusLinuxRuntime.shared.execute(command: "seq 1 1000", workspace: UUID(), onOutput: { line, _ in lines.append(line) })
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(lines.count, 200)
        XCTAssertTrue(lines.last?.contains("展示上限") == true)
        XCTAssertTrue(result.output.hasSuffix("1000\n"))
    }
    func testUserGoalIsExecutedInternallyAndVisibleWithoutUserWritingCommands() async throws {
        let live = NexusLiveExecution(); live.begin(goal: "把三个商品价格求和")
        var tools = NexusToolRegistry()
        tools.register(NexusLinuxTool(workspace: UUID(), onStart: { live.append(.command, $0) }, onOutput: { line, error in live.append(error ? .error : .output, line) }, isEnabled: { true }))
        var replies = [#"{"steps":["计算价格"]}"#, #"{"name":"shell_execute","arguments":{"command":"printf '%s\\n' 12 18 9 | awk '{s+=$1} END {print s}'"}}"#, "三件商品合计39元。", #"{"passed":true,"issues":[]}"#]
        let engine = NexusReasoningEngine(tools: tools, model: { _ in replies.removeFirst() }, onCheckpoint: { live.observe($0.traces) }, onEvent: { live.phase($0) })
        let result = try await engine.run(goal: "把苹果12元、牛奶18元和面包9元求和")
        live.finish(.answered, message: "已生成答复")
        XCTAssertEqual(result.text, "三件商品合计39元。")
        XCTAssertTrue(live.entries.contains { $0.kind == .command })
        XCTAssertTrue(live.entries.contains { $0.kind == .output && $0.text == "39" })
        XCTAssertTrue(live.entries.contains { $0.kind == .result && $0.text.contains("exit_code=0") })
    }
}
