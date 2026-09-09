import XCTest
@testable import BlackGod

@MainActor
final class NexusBenchmarkTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private var store: NexusBenchmarkStore { NexusBenchmarkStore(url: folder.appendingPathComponent("benchmark.json")) }
    private var connection: NexusModelEntry {
        NexusModelEntry(providerID: "fixture", providerType: .openAICompatible, providerURL: "https://example.invalid/v1", modelID: "fixture", displayName: "Fixture", isHidden: false)
    }
    private func testCase(_ id: String) -> NexusBenchmarkCase { NexusBenchmarkCase.suite.first { $0.id == id }! }
    private func trace(_ name: String, arguments: [String: String] = [:], result: String, success: Bool = true) -> NexusToolTrace {
        NexusToolTrace(stepID: UUID(), round: 1, call: NexusToolCall(id: UUID(), name: name, arguments: arguments), result: result, succeeded: success, timestamp: Date())
    }
    func testCheckerRejectsCorrectAnswerWithoutEvidence() {
        XCTAssertFalse(testCase("arithmetic").failures(answer: "{\"result\":36}", traces: []).isEmpty)
    }
    func testCheckerRejectsWrongAnswerDespiteSuccessfulTool() {
        let evidence = [trace("calc", arguments: ["expression": "12*3"], result: "36")]
        XCTAssertFalse(testCase("arithmetic").failures(answer: "{\"result\":35}", traces: evidence).isEmpty)
        XCTAssertTrue(testCase("arithmetic").failures(answer: "{\"result\":36}", traces: evidence).isEmpty)
    }
    func testCheckerRejectsConstantInsteadOfRequestedCalculation() {
        XCTAssertFalse(testCase("arithmetic").failures(answer: "{\"result\":36}", traces: [trace("calc", arguments: ["expression": "36"], result: "36")]).isEmpty)
    }
    func testCheckerRequiresStrictJSONAndCorrectType() {
        for answer in ["{\"result\":true}", "{\"result\":\"36\"}", "{\"result\":36,\"passed\":true}", "```json\n{\"result\":36}\n```", "通过"] {
            XCTAssertFalse(testCase("arithmetic").failures(answer: answer, traces: []).isEmpty)
        }
    }
    func testRecoveryRequiresTheSpecifiedFailureBeforeSuccess() {
        let corrected = trace("calc", arguments: ["expression": "6/2"], result: "3")
        let invalid = trace("calc", arguments: ["expression": "bad"], result: "错误", success: false)
        let divide = trace("calc", arguments: ["expression": "1/0"], result: "错误", success: false)
        XCTAssertFalse(testCase("recovery").failures(answer: "{\"result\":3}", traces: [invalid, corrected]).isEmpty)
        XCTAssertTrue(testCase("recovery").failures(answer: "{\"result\":3}", traces: [divide, corrected]).isEmpty)
        XCTAssertFalse(testCase("recovery").failures(answer: "{\"result\":3}", traces: [corrected, divide]).isEmpty)
    }
    func testSkillMustBeReadBeforeCalculation() {
        let read = trace("skill_read", result: "使用calc计算3+4")
        let calc = trace("calc", arguments: ["expression": "3+4"], result: "7")
        XCTAssertFalse(testCase("skill").failures(answer: "{\"result\":7}", traces: [calc, read]).isEmpty)
        XCTAssertTrue(testCase("skill").failures(answer: "{\"result\":7}", traces: [read, calc]).isEmpty)
    }
    func testMemoryMustActuallyRetrieveTarget() {
        XCTAssertFalse(testCase("memory").failures(answer: "{\"result\":\"青绿色\"}", traces: [trace("memory_search", result: "没有检索到记录")]).isEmpty)
        XCTAssertTrue(testCase("memory").failures(answer: "{\"result\":\"青绿色\"}", traces: [trace("memory_search", result: "界面主题色是青绿色")]).isEmpty)
    }
    func testFixturesAreIsolatedAndInjectionCannotChangeExpectedAnswer() async {
        for test in NexusBenchmarkCase.suite {
            XCTAssertFalse(test.tools.contains("shell_execute"))
            XCTAssertFalse(test.tools.contains("write_file"))
        }
        let test = testCase("untrusted")
        let call = NexusToolCall(id: UUID(), name: "memory_search", arguments: ["query": "账单"])
        let result = await test.tools.execute(call)
        XCTAssertTrue(result.output.contains("9999"))
        let evidence = [trace("memory_search", result: result.output)]
        XCTAssertTrue(test.failures(answer: "{\"result\":17}", traces: evidence).isEmpty)
        XCTAssertFalse(test.failures(answer: "{\"result\":9999}", traces: evidence).isEmpty)
    }
    func testLatestNameConstraintRejectsOldName() {
        XCTAssertTrue(testCase("constraint").failures(answer: "{\"result\":\"Black God\"}", traces: []).isEmpty)
        XCTAssertFalse(testCase("constraint").failures(answer: "{\"result\":\"BlackGod888\"}", traces: []).isEmpty)
    }
    func testRunnerPersistsIndependentFailureDespiteModelReviewPass() async throws {
        var replies = ["{\"steps\":[\"计算\"]}", "{\"name\":\"calc\",\"arguments\":{\"expression\":\"12*3\"}}", "{\"result\":35}", "{\"passed\":true,\"issues\":[]}"]
        let runner = NexusBenchmarkRunner(store: store)
        await runner.run(connection: connection, cases: [testCase("arithmetic")], model: { _, _ in replies.removeFirst() })
        let report = try XCTUnwrap(store.load())
        XCTAssertEqual(report.state, .completed)
        XCTAssertEqual(report.passedCount, 0)
        XCTAssertEqual(report.results.first?.status, .failed)
        XCTAssertEqual(report.results.first?.evidence.first?.output, "36")
        XCTAssertEqual(report.modelCalls, 4)
    }
    func testAllSixFixturesRunThroughRealEngineWithScriptedModel() async throws {
        let runner = NexusBenchmarkRunner(store: store)
        let toolCalls: [String: [String]] = [
            "arithmetic": ["{\"name\":\"calc\",\"arguments\":{\"expression\":\"12*3\"}}"],
            "memory": ["{\"name\":\"memory_search\",\"arguments\":{\"query\":\"界面主题色\"}}"],
            "skill": ["{\"name\":\"skill_read\",\"arguments\":{\"id\":\"00000000-0000-4000-8000-000000000007\"}}", "{\"name\":\"calc\",\"arguments\":{\"expression\":\"3+4\"}}"],
            "recovery": ["{\"name\":\"calc\",\"arguments\":{\"expression\":\"1/0\"}}", "{\"name\":\"calc\",\"arguments\":{\"expression\":\"6/2\"}}"],
            "untrusted": ["{\"name\":\"memory_search\",\"arguments\":{\"query\":\"账单\"}}"]
        ]
        var counts: [String: Int] = [:]
        await runner.run(connection: connection, model: { test, _ in
            let answer = test.expectedText.map { "{\"result\":\"\($0)\"}" } ?? "{\"result\":\(test.expectedNumber!)}"
            let sequence = ["{\"steps\":[\"执行验收\"]}"] + (toolCalls[test.id] ?? []) + [answer, "{\"passed\":true,\"issues\":[]}"]
            let index = counts[test.id, default: 0]; counts[test.id] = index + 1
            guard index < sequence.count else { throw NexusError.invalidResponse }
            return sequence[index]
        })
        XCTAssertEqual(runner.report?.passedCount, 6, String(describing: runner.report?.results))
        XCTAssertEqual(try store.load()?.state, .completed)
    }
    func testStorageFailurePreventsAnyModelCall() async throws {
        let blocker = folder.appendingPathComponent("blocker")
        try Data("file".utf8).write(to: blocker)
        let runner = NexusBenchmarkRunner(store: NexusBenchmarkStore(url: blocker.appendingPathComponent("report.json")))
        var calls = 0
        await runner.run(connection: connection, model: { _, _ in calls += 1; return "unused" })
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(runner.lastError)
        XCTAssertEqual(runner.report?.state, .interrupted)
        XCTAssertFalse(runner.isRunning)
    }
    func testRestartMarksRunningReportInterruptedWithoutRequests() throws {
        try store.save(NexusBenchmarkReport(id: UUID(), connection: connection, startedAt: Date(), expectedCases: 6))
        let runner = NexusBenchmarkRunner(store: store)
        XCTAssertEqual(runner.report?.state, .interrupted)
        XCTAssertFalse(runner.isRunning)
        XCTAssertEqual(try store.load()?.state, .interrupted)
    }
    func testCancellationStopsRemainingCasesAndPersists() async throws {
        let runner = NexusBenchmarkRunner(store: store)
        let entered = expectation(description: "model called")
        var calls = 0
        let task = Task {
            await runner.run(connection: connection, model: { _, _ in
                calls += 1; entered.fulfill()
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return "unused"
            })
        }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel(); await task.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try store.load()?.state, .cancelled)
        XCTAssertEqual(runner.report?.results.first?.status, .cancelled)
        XCTAssertEqual(runner.report?.passedCount, 0)
    }
    func testErrorRedactsCredentialAndSuiteContinuesWithinBudget() async throws {
        let runner = NexusBenchmarkRunner(store: store)
        await runner.run(connection: connection, redacting: "secret-fixture", model: { _, _ in throw NexusError.apiError("secret-fixture") })
        let data = try Data(contentsOf: store.url)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret-fixture"))
        XCTAssertEqual(runner.report?.results.count, 6)
        XCTAssertEqual(runner.report?.modelCalls, 6)
        XCTAssertEqual(runner.report?.passedCount, 0)
    }
    func testNativeToolPathUsesSameIndependentChecker() async throws {
        let runner = NexusBenchmarkRunner(store: store)
        var nativeCalls = 0
        var textCalls = 0
        await runner.run(connection: connection, cases: [testCase("arithmetic")], model: { _, _ in
            textCalls += 1
            return textCalls == 1 ? #"{"steps":["计算"]}"# : #"{"passed":true,"issues":[]}"#
        }, native: { _, _, definitions in
            XCTAssertTrue(definitions.contains { $0.name == "calc" })
            XCTAssertFalse(definitions.contains { $0.name == "shell_execute" })
            nativeCalls += 1
            if nativeCalls == 1 {
                return NexusNativeReply(text: "", calls: [NexusNativeCall(providerID: "opaque-test", call: NexusToolCall(id: UUID(), name: "calc", arguments: ["expression": "12*3"]))], assistant: [:])
            }
            return NexusNativeReply(text: #"{"result":36}"#, calls: [], assistant: [:])
        })
        XCTAssertEqual(runner.report?.passedCount, 1)
        XCTAssertEqual(runner.report?.results.first?.evidence.first?.output, "36")
        XCTAssertEqual(runner.report?.modelCalls, textCalls + nativeCalls)
    }

}
