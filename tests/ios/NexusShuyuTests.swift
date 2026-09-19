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
        for bad in ["", "行：计算(1)", "do: missing(\"x\")", "行：计算(\"1\")\nBAD", String(repeating: "行：计算(\"1\")\n", count: 9), "行：计算(\"1\") → true"] {
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
        XCTAssertEqual(evidence.first?.id, "s1")
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
    func testPlanSearchAndAnalogyStayBounded() async throws {
        var tools = NexusToolRegistry()
        tools.register(NexusCalculatorTool()); tools.register(NexusShuyuTool())
        tools.register(NexusPlanTool()); tools.register(NexusVerifyTool())
        let program = try NexusShuyuEngine.shared.compile("行：规划(\"拆目标\")\n行：检索(\"锚点\")\n行：核对(\"可检查\")")
        XCTAssertEqual(program.version, 2)
        XCTAssertEqual(program.actions.count, 3)
        XCTAssertEqual(program.actions[0].id, "s1")
        let runner = NexusShuyuRunTool(tools: tools)
        let result = await runner.execute(NexusToolCall(id: UUID(), name: runner.name, arguments: ["program": "行：规划(\"拆目标\")\n行：核对(\"可检查\")"]))
        XCTAssertTrue(result.succeeded)
        let identity = try JSONSerialization.jsonObject(with: Data(NexusShuyuEngine.shared.invoke("类比", input: #"["奥形凝起","奥形凝起","奥形凝起"]"#).utf8)) as? [String: Any]
        XCTAssertEqual((identity?["id"] as? NSNumber)?.intValue, 0)
        let plan = try JSONDecoder().decode([[String: String]].self, from: Data(try NexusShuyuEngine.shared.invoke("规划", input: "行：规划(\"拆目标\")").utf8))
        XCTAssertEqual(plan.first?["title"], "拆目标")
        XCTAssertTrue(tools.nativeDefinitions.contains { $0.name == "plan" })
        tools.register(runner)
        XCTAssertTrue(tools.nativeDefinitions.contains { $0.name == "verify" })
    }
    func testNearClockAndRankedSearchStayBounded() async throws {
        var tools = NexusToolRegistry()
        tools.register(NexusCalculatorTool()); tools.register(NexusShuyuTool())
        tools.register(NexusClockTool())
        let program = try NexusShuyuEngine.shared.compile("行：邻近(\"奥形凝起\")\n行：时间(\"Asia/Shanghai\")")
        XCTAssertEqual(program.actions[0].arguments["operation"], "邻近")
        XCTAssertEqual(program.actions[1].tool, "clock")
        let runner = NexusShuyuRunTool(tools: tools)
        let result = await runner.execute(NexusToolCall(id: UUID(), name: runner.name, arguments: ["program": "行：邻近(\"奥形凝起\")"]))
        XCTAssertTrue(result.succeeded)
        let evidence = try JSONDecoder().decode([NexusShuyuStepResult].self, from: Data(result.output.utf8))
        XCTAssertEqual(evidence.first?.id, "s1")
        let neighbors = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("邻近", input: "0").utf8)) as? [[String: Any]]
        XCTAssertEqual(neighbors?.count, 5)
        XCTAssertFalse(neighbors?.contains { ($0["id"] as? NSNumber)?.intValue == 0 } == true)
        let hits = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("检索", input: "光").utf8)) as? [[String: Any]]
        XCTAssertEqual(hits?.first?["拉丁"] as? String, "ryl")
        let pulse = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("一息", input: "1700000000").utf8)) as? [String: Any]
        XCTAssertEqual(pulse?["息"] as? String, "夜")
        XCTAssertEqual(pulse?["轴"] as? String, "态")
        XCTAssertEqual((pulse?["种"] as? [String: Any])?["id"] as? NSNumber, 0)
        XCTAssertNotEqual((pulse?["id"] as? NSNumber)?.intValue, 0)
        let pulseProgram = try NexusShuyuEngine.shared.compile("行：一息(\"1700000000\")")
        XCTAssertEqual(pulseProgram.actions[0].arguments["operation"], "一息")
        let trail = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("余息", input: #"[0,"1700000000",3]"#).utf8)) as? [String: Any]
        XCTAssertEqual((trail?["步"] as? NSNumber)?.intValue, 3)
        XCTAssertEqual((trail?["迹"] as? [Any])?.count, 3)
        XCTAssertEqual((trail?["种"] as? [String: Any])?["id"] as? NSNumber, 0)
        let trailProgram = try NexusShuyuEngine.shared.compile("行：余息(\"1700000000\")")
        XCTAssertEqual(trailProgram.actions[0].arguments["operation"], "余息")
        let echo = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("回息", input: #"[0,"1700000000",3]"#).utf8)) as? [String: Any]
        XCTAssertEqual((echo?["步"] as? NSNumber)?.intValue, 3)
        XCTAssertEqual((echo?["回"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((echo?["种"] as? [String: Any])?["id"] as? NSNumber, 0)
        let echoProgram = try NexusShuyuEngine.shared.compile("行：回息(\"1700000000\")")
        XCTAssertEqual(echoProgram.actions[0].arguments["operation"], "回息")
        let sway = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("摇息", input: #"[0,"1700000000",3]"#).utf8)) as? [String: Any]
        XCTAssertEqual((sway?["摇"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((sway?["侧"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((sway?["种"] as? [String: Any])?["id"] as? NSNumber, 0)
        let swayProgram = try NexusShuyuEngine.shared.compile("行：摇息(\"1700000000\")")
        XCTAssertEqual(swayProgram.actions[0].arguments["operation"], "摇息")
        let land = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("落息", input: #"[0,"0",3]"#).utf8)) as? [String: Any]
        XCTAssertEqual((land?["落"] as? NSNumber)?.boolValue, false)
        XCTAssertEqual((land?["侧"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((land?["种"] as? [String: Any])?["id"] as? NSNumber, 0)
        let landProgram = try NexusShuyuEngine.shared.compile("行：落息(\"1700000000\")")
        XCTAssertEqual(landProgram.actions[0].arguments["operation"], "落息")
        let stir = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("起息", input: #"[0,"60",3]"#).utf8)) as? [String: Any]
        XCTAssertEqual((stir?["起"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((stir?["落"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((stir?["种"] as? [String: Any])?["id"] as? NSNumber, 0)
        let stirProgram = try NexusShuyuEngine.shared.compile("行：起息(\"1700000000\")")
        XCTAssertEqual(stirProgram.actions[0].arguments["operation"], "起息")
        let perch = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("栖息", input: #"[0,"60",3]"#).utf8)) as? [String: Any]
        XCTAssertEqual((perch?["栖"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((perch?["起"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((perch?["种"] as? [String: Any])?["id"] as? NSNumber, 0)
        let perchProgram = try NexusShuyuEngine.shared.compile("行：栖息(\"1700000000\")")
        XCTAssertEqual(perchProgram.actions[0].arguments["operation"], "栖息")
        let turn = try JSONSerialization.jsonObject(with: Data(try NexusShuyuEngine.shared.invoke("转息", input: #"[0,"60",3]"#).utf8)) as? [String: Any]
        XCTAssertEqual((turn?["栖"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((turn?["种"] as? [String: Any])?["id"] as? NSNumber, 0)
        let turnProgram = try NexusShuyuEngine.shared.compile("行：转息(\"1700000000\")")
        XCTAssertEqual(turnProgram.actions[0].arguments["operation"], "转息")
        tools.register(runner)
        XCTAssertTrue(tools.nativeDefinitions.contains { $0.name == "clock" })
    }
    func testAwakenWritesPulseNoteWithoutWaitingForPrompt() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in false })
        vm.awaken(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNotNil(vm.pulseNote)
        XCTAssertTrue(vm.pulseNote?.contains(" · ") == true)
        XCTAssertTrue(vm.pulseNote?.contains(" → ") == true)
        XCTAssertTrue(vm.pulseNote?.contains("↷") == true || vm.pulseNote?.contains("↘") == true)
        XCTAssertNotNil(vm.pulseWord)
        XCTAssertTrue(["在场", "该练"].contains(vm.currentMood))
        XCTAssertNotEqual(vm.currentMood, "就绪")
        let first = vm.pulseWord
        vm.awaken(now: Date(timeIntervalSince1970: 1_700_000_180))
        XCTAssertEqual(vm.pulseNote?.contains(first ?? ""), true)
        XCTAssertTrue(vm.pulseNote?.contains("↷") == true || vm.pulseNote?.contains("↘") == true || vm.pulseNote?.contains("⤵") == true)
    }
}
