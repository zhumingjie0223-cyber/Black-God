import XCTest
@testable import BlackGod

private struct ShuyuProbe: NexusTool {
    let name: String
    let value: String
    let probe: () -> Void
    func execute(_ call: NexusToolCall) async -> NexusToolResult { probe(); return NexusToolResult(callID: call.id, output: value, succeeded: true) }
}
@MainActor
final class NexusShuyuTests: XCTestCase {
    func testBundledEngineRoundTripsKnownSeedsAndPreservesIDs() throws {
        let engine = NexusShuyuEngine.shared
        for seed in ["神枢", "Black God", "枢语🌱"] { XCTAssertEqual(try engine.invoke("往返", input: seed), "true") }
        let word = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(engine.invoke("造词", input: "神枢").utf8)) as? [String: Any])
        XCTAssertEqual((word["id"] as? NSNumber)?.int64Value, 780009883)
        XCTAssertEqual(try engine.invoke("汉译编号", input: word["汉"] as! String), "780009883")
        XCTAssertEqual(try engine.invoke("拉丁编号", input: word["词"] as! String), "780009883")
        XCTAssertTrue(try engine.invoke("容量", input: "").contains("7667712000"))
    }
    func testGrammarHandlesEscapesAndRejectsUnsupportedOrPartialProgram() throws {
        let program = try NexusShuyuEngine.shared.compile(#"行：执行("printf \"a,b)→c\"")"#)
        XCTAssertEqual(program.actions[0].arguments["command"], "printf \"a,b)→c\"")
        for bad in ["", "行：计算(1)", "do: missing(\"x\")", "行：计算(\"1\")\nBAD", String(repeating: "行：计算(\"1\")\n", count: 5), "行：计算(\"1\") → true"] {
            XCTAssertThrowsError(try NexusShuyuEngine.shared.compile(bad))
        }
    }
    func testInputIsNeverEvaluatedAsJavaScript() throws {
        let text = "\");globalThis.pwned=true;//"
        XCTAssertEqual(try NexusShuyuEngine.shared.invoke("往返", input: text), "true")
        XCTAssertThrowsError(try NexusShuyuEngine.shared.invoke("解码", input: text))
        XCTAssertThrowsError(try NexusShuyuEngine.shared.invoke("质数", input: "10001"))
        XCTAssertThrowsError(try NexusShuyuEngine.shared.invoke("质数", input: "-1"))
        XCTAssertEqual(try NexusShuyuEngine.shared.invoke("质数", input: "20"), "[2,3,5,7,11,13,17,19]")
    }
    func testUnavailableActionRejectsEntireProgramBeforeFirstSideEffect() async {
        var calls = 0; var tools = NexusToolRegistry()
        tools.register(ShuyuProbe(name: "calc", value: "1", probe: { calls += 1 }))
        let tool = NexusShuyuRunTool(tools: tools)
        let result = await tool.execute(NexusToolCall(id: UUID(), name: tool.name, arguments: ["program": "行：计算(\"1\")\n行：执行(\"echo x\")"]))
        XCTAssertFalse(result.succeeded); XCTAssertEqual(calls, 0)
    }
    func testExpectedMismatchStopsFurtherActions() async throws {
        var calls = 0; var tools = NexusToolRegistry()
        tools.register(ShuyuProbe(name: "calc", value: "35", probe: { calls += 1 }))
        let tool = NexusShuyuRunTool(tools: tools)
        let result = await tool.execute(NexusToolCall(id: UUID(), name: tool.name, arguments: ["program": "行：计算(\"12*3\") → \"36\"\n行：计算(\"1+1\")"]))
        XCTAssertFalse(result.succeeded); XCTAssertEqual(calls, 1)
        let evidence = try JSONDecoder().decode([NexusShuyuStepResult].self, from: Data(result.output.utf8))
        XCTAssertEqual(evidence.first?.matched, false)
    }
    func testRealCalculationAndLanguageComposeThroughSameTools() async throws {
        var tools = NexusToolRegistry(); tools.register(NexusCalculatorTool()); tools.register(NexusShuyuTool())
        let tool = NexusShuyuRunTool(tools: tools)
        let result = await tool.execute(NexusToolCall(id: UUID(), name: tool.name, arguments: ["program": "行：计算(\"12*3\") → \"36\"\n行：枢语(\"往返\",\"神枢\") → \"true\""]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(try JSONDecoder().decode([NexusShuyuStepResult].self, from: Data(result.output.utf8)).count, 2)
        tools.register(tool)
        XCTAssertTrue(tools.nativeDefinitions.contains { $0.name == "shuyu_execute" })
    }
}
