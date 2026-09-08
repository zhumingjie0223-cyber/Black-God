import XCTest
@testable import BlackGod

private struct NativeSingleStepPlanner: NexusPlanning {
    func makePlan(for goal: String) -> NexusTaskPlan {
        NexusTaskPlan(id: UUID(), goal: goal, steps: [NexusTaskStep(title: goal)], createdAt: Date())
    }
}

@MainActor
final class NexusNativeAgentTests: XCTestCase {
    private func registry() -> NexusToolRegistry {
        var registry = NexusToolRegistry()
        registry.register(NexusCalculatorTool())
        registry.register(NexusClockTool())
        return registry
    }
    private func reply(_ calls: [[String: Any]] = [], text: String = "") throws -> NexusNativeReply {
        var message: [String: Any] = ["role": "assistant", "content": text]
        if !calls.isEmpty { message["tool_calls"] = calls }
        return try NexusNativeCodec.decode(JSONSerialization.data(withJSONObject: ["choices": [["message": message, "finish_reason": calls.isEmpty ? "stop" : "tool_calls"]]]), type: .openAICompatible)
    }
    private func call(_ id: String = "call_not_a_uuid", name: String = "calc", arguments: String = "{\"expression\":\"12*3\"}") -> [String: Any] {
        ["id": id, "type": "function", "function": ["name": name, "arguments": arguments]]
    }
    private func entry(_ type: NexusProviderType) -> NexusModelEntry {
        NexusModelEntry(providerID: "test", providerType: type, providerURL: "https://fixture.invalid/v1", modelID: "fixture", displayName: "test", isHidden: false)
    }
    func testOpaqueIDsSurviveOpenAIResultReplay() throws {
        let response = try reply([call()])
        XCTAssertEqual(response.calls.first?.providerID, "call_not_a_uuid")
        let native = try XCTUnwrap(response.calls.first)
        let result = NexusToolResult(callID: native.call.id, output: "36", succeeded: true)
        let data = try NexusNativeCodec.body(model: entry(.openAICompatible), messages: [.text(role: "user", content: "计算"), .assistant(response), .results([(native, result)])], tools: registry().nativeDefinitions)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.last?["role"] as? String, "tool")
        XCTAssertEqual(messages.last?["tool_call_id"] as? String, "call_not_a_uuid")
        XCTAssertEqual(messages.last?["content"] as? String, "36")
        XCTAssertEqual(body["stream"] as? Bool, false)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        XCTAssertNotNil((tools.first?["function"] as? [String: Any])?["parameters"])
    }
    func testAnthropicBlocksAndToolResultPairing() throws {
        let object: [String: Any] = ["stop_reason": "tool_use", "content": [
            ["type": "text", "text": "开始计算"],
            ["type": "tool_use", "id": "toolu_example", "name": "calc", "input": ["expression": "3+4"]]
        ]]
        let response = try NexusNativeCodec.decode(JSONSerialization.data(withJSONObject: object), type: .anthropic)
        let native = try XCTUnwrap(response.calls.first)
        let result = NexusToolResult(callID: native.call.id, output: "7", succeeded: true)
        let data = try NexusNativeCodec.body(model: entry(.anthropic), messages: [.assistant(response), .results([(native, result)])], tools: registry().nativeDefinitions)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let block = (messages.last?["content"] as? [[String: Any]])?.first
        XCTAssertEqual(block?["tool_use_id"] as? String, "toolu_example")
        XCTAssertEqual(block?["is_error"] as? Bool, false)
        XCTAssertNotNil((body["tools"] as? [[String: Any]])?.first?["input_schema"])
    }
    func testMalformedArgumentsDuplicateIDsAndExcessiveCallsFailBeforeExecution() throws {
        for calls in [[call(arguments: "{")], [call(arguments: "{\"expression\":12}")], [call(), call()], (0..<9).map { call("call_\($0)") }] {
            XCTAssertThrowsError(try reply(calls))
        }
    }
    func testTruncationAndMismatchedCompletionCannotExecute() throws {
        for reason in ["length", "content_filter", "stop"] {
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["tool_calls": [call()]], "finish_reason": reason]]])
            XCTAssertThrowsError(try NexusNativeCodec.decode(data, type: .openAICompatible))
        }
    }
    func testOnlyImplementedToolsAreAdvertisedAndArgumentsValidated() {
        let tools = registry()
        XCTAssertEqual(Set(tools.nativeDefinitions.map(\.name)), ["clock", "calc"])
        for call in [NexusToolCall(id: UUID(), name: "shell", arguments: [:]),
                     NexusToolCall(id: UUID(), name: "calc", arguments: [:]),
                     NexusToolCall(id: UUID(), name: "calc", arguments: ["expression": "3+4", "unexpected": "x"])] {
            XCTAssertNotNil(tools.validateNative(call))
        }
    }
    func testNativeLoopExecutesAndReturnsRealResult() async throws {
        var rounds = 0
        let executor = NexusExecutor(planner: NativeSingleStepPlanner(), verifier: NexusContentVerifier(), tools: registry(), nativeTurn: { messages, _ in
            rounds += 1
            if rounds == 1 { return try self.reply([self.call()]) }
            guard case .results(let results) = messages.last else { throw NexusError.invalidResponse }
            XCTAssertEqual(results.first?.1.output, "36")
            return try self.reply(text: "总价36元")
        })
        let answer = await executor.run(goal: "计算12*3")
        XCTAssertEqual(answer, "总价36元")
        XCTAssertEqual(executor.toolTraces.count, 1)
        XCTAssertNil(executor.lastError)
    }
    func testMultipleToolsReturnEveryMatchingID() async throws {
        var round = 0
        let executor = NexusExecutor(planner: NativeSingleStepPlanner(), verifier: NexusContentVerifier(), tools: registry(), nativeTurn: { messages, _ in
            round += 1
            if round == 1 { return try self.reply([self.call("a"), self.call("b", arguments: "{\"expression\":\"2+3\"}")]) }
            guard case .results(let results) = messages.last else { throw NexusError.invalidResponse }
            XCTAssertEqual(results.map { $0.0.providerID }, ["a", "b"])
            XCTAssertEqual(results.map { $0.1.output }, ["36", "5"])
            return try self.reply(text: "36和5")
        })
        _ = await executor.run(goal: "计算两项")
        XCTAssertEqual(executor.toolTraces.count, 2)
    }
    func testInvalidToolReturnsErrorAndModelCanRepair() async throws {
        var round = 0
        let executor = NexusExecutor(planner: NativeSingleStepPlanner(), verifier: NexusContentVerifier(), tools: registry(), nativeTurn: { messages, _ in
            round += 1
            if round == 1 { return try self.reply([self.call(name: "shell")]) }
            guard case .results(let results) = messages.last else { throw NexusError.invalidResponse }
            if round == 2 {
                XCTAssertFalse(results[0].1.succeeded)
                return try self.reply([self.call("second")])
            }
            XCTAssertEqual(results[0].1.output, "36")
            return try self.reply(text: "36")
        })
        let answer = await executor.run(goal: "计算")
        XCTAssertEqual(answer, "36")
    }
    func testRepeatedCallsReuseEvidenceAndStopAtLimit() async throws {
        let executor = NexusExecutor(planner: NativeSingleStepPlanner(), verifier: NexusContentVerifier(), tools: registry(), nativeTurn: { _, _ in try self.reply([self.call(UUID().uuidString)]) }, maxToolRounds: 3)
        let answer = await executor.run(goal: "计算")
        XCTAssertEqual(answer, "")
        XCTAssertEqual(executor.toolTraces.count, 1)
        XCTAssertTrue(executor.lastError?.contains("上限") == true)
    }
    func testGlobalBudgetCountsNativeRequests() async throws {
        let engine = NexusReasoningEngine(tools: registry(), maxCalls: 2, model: { _ in "{\"steps\":[\"计算\"]}" }, nativeTurn: { _, _ in try self.reply([self.call()]) })
        do { _ = try await engine.run(goal: "计算"); XCTFail("必须受全局预算限制") } catch {}
        XCTAssertEqual(engine.modelCalls, 2)
    }
    func testCancelledNativeReplyDoesNotExecuteTool() async throws {
        let executor = NexusExecutor(planner: NativeSingleStepPlanner(), verifier: NexusContentVerifier(), tools: registry(), nativeTurn: { _, _ in
            try await Task.sleep(for: .seconds(5))
            return try self.reply([self.call()])
        })
        let task = Task { await executor.run(goal: "计算") }
        await Task.yield()
        task.cancel()
        _ = await task.value
        XCTAssertTrue(executor.toolTraces.isEmpty)
    }
    func testNativeLoopFeedsEvidenceIntoReview() async throws {
        var prompts: [String] = []
        var nativeRounds = 0
        let engine = NexusReasoningEngine(tools: registry(), model: { prompt in
            prompts.append(prompt)
            return prompts.count == 1 ? "{\"steps\":[\"计算\"]}" : "{\"passed\":true,\"issues\":[]}"
        }, nativeTurn: { _, _ in
            nativeRounds += 1
            return try nativeRounds == 1 ? self.reply([self.call()]) : self.reply(text: "36")
        })
        let outcome = try await engine.run(goal: "计算12*3")
        XCTAssertTrue(outcome.reviewPassed)
        XCTAssertTrue(prompts.last?.contains("实际结果：36") == true)
        XCTAssertEqual(engine.modelCalls, 4)
    }
}


@MainActor
extension NexusNativeAgentTests {
    func testReasoningRepairUsesNativeToolsAndReviewsFreshEvidence() async throws {
        var textCalls = 0
        var nativeCalls = 0
        let engine = NexusReasoningEngine(tools: registry(), model: { prompt in
            textCalls += 1
            if textCalls == 1 { return #"{"steps":["计算"]}"# }
            if textCalls == 2 { return #"{"passed":false,"issues":["需要工具验证"]}"# }
            XCTAssertTrue(prompt.contains("实际结果：36"))
            return #"{"passed":true,"issues":[]}"#
        }, nativeTurn: { messages, _ in
            nativeCalls += 1
            if nativeCalls == 1 { return try self.reply(text: "猜测为35") }
            if nativeCalls == 2 {
                guard case .text(_, let prompt) = messages.first else { throw NexusError.invalidResponse }
                XCTAssertTrue(prompt.contains("已有工具证据"))
                return try self.reply([self.call()])
            }
            guard case .results(let results) = messages.last else { throw NexusError.invalidResponse }
            XCTAssertEqual(results.first?.1.output, "36")
            return try self.reply(text: "已计算为36")
        })
        let result = try await engine.run(goal: "计算12乘3")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(result.text, "已计算为36")
        XCTAssertEqual(engine.modelCalls, 6)
        XCTAssertEqual(nativeCalls, 3)
    }
}
