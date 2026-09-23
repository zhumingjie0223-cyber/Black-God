import XCTest
@testable import BlackGod

private struct BoundaryPlanner: NexusPlanning {
    func makePlan(for goal: String) -> NexusTaskPlan {
        NexusTaskPlan(id: UUID(), goal: goal, steps: [NexusTaskStep(title: goal)], createdAt: Date())
    }
}

private actor BoundaryExecutions {
    private(set) var count = 0
    func record() { count += 1 }
}

private struct BoundaryTool: NexusTool {
    let name = "calc"
    let executions: BoundaryExecutions
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        await executions.record()
        return NexusToolResult(callID: call.id, output: "unexpected execution", succeeded: true)
    }
}

@MainActor
final class NexusToolBoundaryTests: XCTestCase {
    private func textCalls(_ count: Int) throws -> String {
        let calls = (0..<count).map { ["name": "calc", "arguments": ["expression": "\($0)+1"]] as [String: Any] }
        return String(decoding: try JSONSerialization.data(withJSONObject: calls), as: UTF8.self)
    }

    private func textReply(_ text: String, type: NexusProviderType = .openAICompatible) throws -> NexusNativeReply {
        let object: [String: Any]
        switch type {
        case .openAICompatible:
            object = ["choices": [["message": ["role": "assistant", "content": text], "finish_reason": "stop"]]]
        case .anthropic:
            object = ["content": [["type": "text", "text": text]], "stop_reason": "end_turn"]
        case .gemini:
            object = ["candidates": [["content": ["role": "model", "parts": [["text": text]]], "finishReason": "STOP"]]]
        case .responses:
            object = ["status": "completed", "output": [["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]]]
        }
        return try NexusNativeCodec.decode(JSONSerialization.data(withJSONObject: object), type: type)
    }

    private func assertNoExecution(_ reply: NexusNativeReply, errorContains: String, file: StaticString = #filePath, line: UInt = #line) async {
        let executions = BoundaryExecutions()
        var registry = NexusToolRegistry()
        registry.register(BoundaryTool(executions: executions))
        let executor = NexusExecutor(planner: BoundaryPlanner(), tools: registry, nativeTurn: { _, _ in reply })
        let output = await executor.run(goal: "验证边界")
        XCTAssertEqual(output, "", file: file, line: line)
        XCTAssertTrue(executor.lastError?.contains(errorContains) == true, executor.lastError ?? "missing error", file: file, line: line)
        let count = await executions.count
        XCTAssertEqual(count, 0, file: file, line: line)
        XCTAssertTrue(executor.toolTraces.isEmpty, file: file, line: line)
    }

    func testNinthTextToolCallIsRejectedBeforeAnySideEffect() async throws {
        for text in [try textCalls(9), "```json\n\(try textCalls(9))\n```"] {
            await assertNoExecution(try textReply(text), errorContains: "单轮上限")
        }
    }

    func testTextProtocolRejectsNinthCallWithoutExecutingFirstEight() async throws {
        for text in [try textCalls(9), "```json\n\(try textCalls(9))\n```"] {
            let executions = BoundaryExecutions()
            var registry = NexusToolRegistry()
            registry.register(BoundaryTool(executions: executions))
            let executor = NexusExecutor(planner: BoundaryPlanner(), model: { _ in text }, tools: registry)
            let answer = await executor.run(goal: "验证普通文本协议数量边界")
            XCTAssertEqual(answer, "")
            XCTAssertTrue(executor.lastError?.contains("单轮上限") == true)
            let count = await executions.count
            XCTAssertEqual(count, 0)
            XCTAssertTrue(executor.toolTraces.isEmpty)
        }
    }

    func testTextProtocolKeepsExplainedExamplesVisibleWithoutExecution() async throws {
        let text = "以下仅演示格式：\n```json\n\(try textCalls(1))\n```\n这些参数不代表执行请求。"
        let executions = BoundaryExecutions()
        var registry = NexusToolRegistry()
        registry.register(BoundaryTool(executions: executions))
        let executor = NexusExecutor(planner: BoundaryPlanner(), model: { _ in text }, tools: registry)
        let answer = await executor.run(goal: "解释工具格式")
        XCTAssertEqual(answer, text)
        let count = await executions.count
        XCTAssertEqual(count, 0)
        XCTAssertTrue(executor.toolTraces.isEmpty)
        XCTAssertNil(executor.lastError)
    }

    func testTextProtocolRejectsOversizedArgumentsBeforeExecution() async throws {
        let object: [String: Any] = ["name": "calc", "arguments": ["expression": String(repeating: "x", count: 2_000_001)]]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let executions = BoundaryExecutions()
        var registry = NexusToolRegistry()
        registry.register(BoundaryTool(executions: executions))
        let executor = NexusExecutor(planner: BoundaryPlanner(), model: { _ in text }, tools: registry)
        let answer = await executor.run(goal: "验证普通文本协议大小边界")
        XCTAssertEqual(answer, "")
        XCTAssertTrue(executor.lastError?.contains("接收上限") == true)
        let count = await executions.count
        XCTAssertEqual(count, 0)
        XCTAssertTrue(executor.toolTraces.isEmpty)
    }

    func testTextProtocolAcceptsEightCallsInPlainOrFencedJSON() async throws {
        for text in [try textCalls(8), "```json\n\(try textCalls(8))\n```"] {
            let executions = BoundaryExecutions()
            var registry = NexusToolRegistry()
            registry.register(BoundaryTool(executions: executions))
            var round = 0
            let executor = NexusExecutor(planner: BoundaryPlanner(), model: { _ in
                round += 1
                return round == 1 ? text : "已收到八次工具结果。"
            }, tools: registry)
            let answer = await executor.run(goal: "执行八个有效工具调用")
            XCTAssertEqual(answer, "已收到八次工具结果。")
            let count = await executions.count
            XCTAssertEqual(count, 8)
            XCTAssertEqual(executor.toolTraces.count, 8)
            XCTAssertNil(executor.lastError)
        }
    }

    func testExecutorChecksNativeCallCountEvenWithoutTransportDecoder() async {
        let calls = (0..<9).map {
            NexusNativeCall(providerID: "call_\($0)", call: NexusToolCall(id: UUID(), name: "calc", arguments: ["expression": "\($0)+1"]))
        }
        await assertNoExecution(NexusNativeReply(text: "", calls: calls, assistant: [:]), errorContains: "单轮上限")
    }

    func testExecutorRejectsOversizedArgumentsBeforeAnySideEffect() async {
        let call = NexusNativeCall(providerID: "oversized", call: NexusToolCall(id: UUID(), name: "calc",
            arguments: ["expression": String(repeating: "x", count: 2_000_001)]))
        await assertNoExecution(NexusNativeReply(text: "", calls: [call], assistant: [:]), errorContains: "接收上限")
    }

    func testEightOpenAITextCallsKeepMatchingReplayIDs() throws {
        let reply = try textReply("```json\n\(try textCalls(8))\n```").promotingTextCalls()
        XCTAssertEqual(reply.calls.count, 8)
        let replay = try XCTUnwrap(reply.assistant["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(replay.compactMap { $0["id"] as? String }, reply.calls.map(\.providerID))
        XCTAssertEqual(reply.calls.last?.call.arguments["expression"], "7+1")
    }

    func testProtocolIncompatibleTextToolsFailBeforeAnySideEffect() async throws {
        for type in [NexusProviderType.anthropic, .gemini, .responses] {
            let reply = try textReply(textCalls(1), type: type)
            XCTAssertEqual(reply.providerType, type)
            await assertNoExecution(reply, errorContains: "需要原生工具调用")
        }
    }

    func testExplainedToolExamplesStayVisibleAndDoNotExecute() async throws {
        let text = "下面只是工具格式示例，请勿执行：\n```json\n\(try textCalls(1))\n```"
        for type in [NexusProviderType.openAICompatible, .anthropic, .gemini, .responses] {
            let reply = try textReply(text, type: type)
            let executions = BoundaryExecutions()
            var registry = NexusToolRegistry()
            registry.register(BoundaryTool(executions: executions))
            let executor = NexusExecutor(planner: BoundaryPlanner(), tools: registry, nativeTurn: { _, _ in reply })
            let answer = await executor.run(goal: "解释工具格式")
            XCTAssertEqual(answer, text)
            let count = await executions.count
            XCTAssertEqual(count, 0)
            XCTAssertTrue(executor.toolTraces.isEmpty)
        }
    }

    private func toolEvent(type: NexusProviderType, index: Int, name: String? = nil, fragment: String? = nil) throws -> String {
        let object: [String: Any]
        if type == .anthropic {
            if let name {
                object = ["type": "content_block_start", "index": index, "content_block": ["type": "tool_use", "name": name]]
            } else {
                object = ["type": "content_block_delta", "index": index, "delta": ["type": "input_json_delta", "partial_json": fragment ?? ""]]
            }
        } else {
            var function: [String: Any] = [:]
            if let name { function["name"] = name }
            if let fragment { function["arguments"] = fragment }
            object = ["choices": [["delta": ["tool_calls": [["index": index, "function": function]]]]]]
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func testToolFragmentsCannotExceedCumulativeUTF8Budget() throws {
        for type in [NexusProviderType.openAICompatible, .anthropic] {
            var content = NexusStreamContent(providerType: type)
            _ = try content.receive(toolEvent(type: type, index: 0, name: "calc"))
            // Every event is below the existing 256 KiB line limit; their combined UTF-8 size is not.
            let fragment = String(repeating: "中", count: 50_000)
            let event = try toolEvent(type: type, index: 0, fragment: fragment)
            for _ in 0..<13 { XCTAssertNoThrow(try content.receive(event)) }
            XCTAssertThrowsError(try content.receive(event)) { error in
                XCTAssertTrue(error.localizedDescription.contains("接收上限"))
            }
        }
    }

    func testTextAndToolFragmentsShareReceiveBudget() throws {
        var content = NexusStreamContent(providerType: .openAICompatible)
        let textEvent: [String: Any] = ["choices": [["delta": ["content": String(repeating: "t", count: 150_000)]]]]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: textEvent), as: UTF8.self)
        for _ in 0..<10 { _ = try content.receive(text) }
        _ = try content.receive(toolEvent(type: .openAICompatible, index: 0, name: "calc"))
        let fragment = try toolEvent(type: .openAICompatible, index: 0, fragment: String(repeating: "x", count: 150_000))
        for _ in 0..<3 { _ = try content.receive(fragment) }
        XCTAssertThrowsError(try content.receive(fragment))
    }

    func testNinthStreamedToolCallFailsForBothProtocols() throws {
        for type in [NexusProviderType.openAICompatible, .anthropic] {
            var content = NexusStreamContent(providerType: type)
            // Anthropic block indices may include preceding text/thought blocks, so index is not call count.
            for index in 10..<18 { _ = try content.receive(toolEvent(type: type, index: index, name: "clock")) }
            XCTAssertThrowsError(try content.receive(toolEvent(type: type, index: 18, name: "clock")))
        }
    }
}
