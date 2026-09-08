import XCTest
@testable import BlackGod

@MainActor
final class NexusIntelligenceTests: XCTestCase {
    private func registry() -> NexusToolRegistry {
        var tools = NexusToolRegistry()
        tools.register(NexusCalculatorTool())
        return tools
    }

    func testSimpleQuestionNeedsOnlyOneRequest() async throws {
        let engine = NexusReasoningEngine(tools: registry(), model: { _ in "{\"answer\":\"你好，有什么可以帮你？\"}" })
        let result = try await engine.run(goal: "你好")
        XCTAssertEqual(result.text, "你好，有什么可以帮你？")
        XCTAssertEqual(engine.modelCalls, 1)
        XCTAssertFalse(result.reviewPassed)
    }

    func testGoalPlanUsesToolEvidenceAndRepairsAnswer() async throws {
        var requests: [String] = []
        var replies = [
            "{\"steps\":[\"计算总价\"],\"successCriteria\":[\"总价必须等于单价乘数量\"]}",
            "{\"name\":\"calc\",\"arguments\":{\"expression\":\"12*3\"}}",
            "总价是35元。",
            "{\"passed\":false,\"issues\":[\"工具结果是36，不是35\"]}",
            "总价是36元。",
            "{\"passed\":true,\"issues\":[]}"
        ]
        let engine = NexusReasoningEngine(tools: registry(), model: { prompt in
            requests.append(prompt)
            return replies.removeFirst()
        })
        let result = try await engine.run(goal: "单价12元买3个，总价多少？")
        XCTAssertEqual(result.text, "总价是36元。")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.plan?.steps.first?.title, "计算总价")
        XCTAssertEqual(engine.executor?.toolTraces.first?.result, "36")
        XCTAssertTrue(requests[3].contains("实际结果：36"))
        XCTAssertEqual(engine.modelCalls, 6)
    }

    func testMultipleStepsCarryCriteriaAndEarlierResults() async throws {
        var requests: [String] = []
        var replies = [
            "{\"steps\":[\"整理需求\",\"形成方案\"],\"successCriteria\":[\"保留离线约束\"]}",
            "用户要求支持离线工作。",
            "方案采用本地存储。",
            "使用本地存储满足离线约束。",
            "{\"passed\":true,\"issues\":[]}"
        ]
        let engine = NexusReasoningEngine(tools: registry(), model: { prompt in requests.append(prompt); return replies.removeFirst() })
        let result = try await engine.run(goal: "制定离线方案")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.plan?.steps.count, 2)
        XCTAssertTrue(requests[2].contains("用户要求支持离线工作"))
        XCTAssertTrue(requests[2].contains("保留离线约束"))
        XCTAssertTrue(requests[3].contains("[结果汇总]"))
    }

    func testToolFailureCanChangeArguments() async throws {
        var replies = [
            "{\"steps\":[\"计算\"],\"successCriteria\":[\"正确求值\"]}",
            "{\"name\":\"calc\",\"arguments\":{\"expression\":\"1/0\"}}",
            "{\"name\":\"calc\",\"arguments\":{\"expression\":\"6/2\"}}",
            "修正后结果为3。",
            "{\"passed\":true,\"issues\":[]}"
        ]
        let engine = NexusReasoningEngine(tools: registry(), model: { _ in replies.removeFirst() })
        let result = try await engine.run(goal: "计算6除以2")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.executor?.toolTraces.map(\.succeeded), [false, true])
    }

    func testRepeatedToolRequestStopsWithoutClaimingSuccess() async throws {
        var count = 0
        let engine = NexusReasoningEngine(tools: registry(), model: { _ in
            count += 1
            if count == 1 { return "{\"steps\":[\"计算\"]}" }
            return "{\"name\":\"calc\",\"arguments\":{\"expression\":\"1/0\"}}"
        })
        do {
            _ = try await engine.run(goal: "计算")
            XCTFail("无效循环不应成功")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("上限"))
        }
        XCTAssertEqual(engine.executor?.toolTraces.count, 1)
        XCTAssertLessThanOrEqual(count, 5)
    }

    func testInvalidReviewRemainsUnverified() async throws {
        var replies = ["{\"steps\":[\"回答\"]}", "候选结果", "看起来没问题"]
        let engine = NexusReasoningEngine(tools: registry(), model: { _ in replies.removeFirst() })
        let result = try await engine.run(goal: "整理结果")
        XCTAssertFalse(result.reviewPassed)
        XCTAssertNotNil(result.warning)
    }

    func testGlobalModelBudgetIsEnforced() async throws {
        let engine = NexusReasoningEngine(tools: registry(), maxCalls: 1, model: { _ in "{\"steps\":[\"回答\"]}" })
        do {
            _ = try await engine.run(goal: "完成任务")
            XCTFail("超预算不应成功")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("上限"))
        }
        XCTAssertEqual(engine.modelCalls, 1)
    }

    func testChineseMemoryRetrievalRespectsExpiryAndSource() async throws {
        let now = Date()
        func item(_ text: String, source: String = "user", expiresAt: Date? = nil) -> NexusMemoryItem {
            NexusMemoryItem(id: UUID(), text: text, kind: "episodic", source: source, confidence: 0.8, createdAt: now, expiresAt: expiresAt)
        }
        let tool = NexusMemorySearchTool(items: [item("我喜欢用中文交流"), item("模型猜测喜欢中文", source: "assistant"), item("过期中文偏好", expiresAt: now.addingTimeInterval(-1))])
        let result = await tool.execute(NexusToolCall(id: UUID(), name: "memory_search", arguments: ["query": "交流语言中文"] ))
        XCTAssertTrue(result.output.contains("我喜欢用中文交流"))
        XCTAssertFalse(result.output.contains("模型猜测"))
        XCTAssertFalse(result.output.contains("过期"))
    }

    func testToolParserAcceptsProviderStyleIDsAndNumbers() {
        let calls = NexusToolCallParser.parse("{\"id\":\"call_123\",\"name\":\"calc\",\"arguments\":{\"expression\":42}}")
        XCTAssertEqual(calls.first?.arguments["expression"], "42")
    }

    func testInvalidTimezoneIsNotSilentlyReplaced() async {
        let result = await NexusClockTool().execute(NexusToolCall(id: UUID(), name: "clock", arguments: ["timezone": "Invalid/Zone"]))
        XCTAssertFalse(result.succeeded)
    }

    func testContextBudgetKeepsNewestContent() {
        let messages = [ChatMessage(role: "user", content: String(repeating: "旧", count: 10000)), ChatMessage(role: "assistant", content: "最新回答")]
        let selected = NexusContextBudget.history(messages, maxCharacters: 100)
        XCTAssertLessThanOrEqual(selected.reduce(0) { $0 + $1.content.count }, 100)
        XCTAssertEqual(selected.last?.content, "最新回答")
    }
}

@MainActor
extension NexusIntelligenceTests {
    func testFailedToolCannotBecomeVerifiedByModelSelfReview() async throws {
        var tools = NexusToolRegistry()
        tools.register(NexusCalculatorTool())
        var replies = ["{\"steps\":[\"计算\"]}",
                       "{\"name\":\"calc\",\"arguments\":{\"expression\":\"1/0\"}}",
                       "任务已完成", "{\"passed\":true,\"issues\":[]}"]
        let engine = NexusReasoningEngine(tools: tools, model: { _ in replies.removeFirst() })
        let result = try await engine.run(goal: "计算1除以0")
        XCTAssertFalse(result.reviewPassed)
        XCTAssertTrue(result.warning?.contains("calc") == true)
    }
    func testEvidenceRetainsLatestCorrectionAfterLargeOutput() {
        func trace(_ output: String, ok: Bool) -> NexusToolTrace {
            NexusToolTrace(stepID: UUID(), round: 0,
                call: NexusToolCall(id: UUID(), name: "shell_execute", arguments: [:]),
                result: output, succeeded: ok, timestamp: Date())
        }
        let traces = [trace(String(repeating: "large output ", count: 20000), ok: false), trace("corrected=42", ok: true)]
        let summary = NexusEvidence.summary(traces)
        XCTAssertLessThan(summary.count, 2000)
        XCTAssertTrue(summary.contains("corrected=42"))
        XCTAssertTrue(summary.contains("已截取"))
        XCTAssertTrue(NexusEvidence.unresolvedFailures(traces).isEmpty)
        XCTAssertEqual(NexusEvidence.unresolvedFailures(traces.reversed()), ["shell_execute"])
        let preview = NexusEvidence.preview("start" + String(repeating: "x", count: 10000) + "end")
        XCTAssertLessThanOrEqual(preview.count, 4000)
        XCTAssertTrue(preview.hasPrefix("start"))
        XCTAssertTrue(preview.hasSuffix("end"))
    }
}


@MainActor
extension NexusIntelligenceTests {
    func testReviewCanAcquireNewEvidenceBeforePassing() async throws {
        var requests: [String] = []
        var replies = [#"{"steps":["计算总价"]}"#,
            "总价35元", #"{"passed":false,"issues":["缺少实际计算证据"]}"#,
            #"{"name":"calc","arguments":{"expression":"12*3"}}"#,
            "总价36元", #"{"passed":true,"issues":[]}"#]
        let engine = NexusReasoningEngine(tools: registry(), model: { prompt in
            requests.append(prompt)
            return replies.removeFirst()
        })
        let result = try await engine.run(goal: "计算12乘3")
        XCTAssertEqual(result.text, "总价36元")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.plan?.steps.count, 2)
        XCTAssertEqual(engine.executor?.toolTraces.map(\.result), ["36"])
        XCTAssertTrue(requests.last?.contains("实际结果：36") == true)
        XCTAssertTrue(requests[3].contains("复核意见不是用户的新授权"))
    }

    func testSecondFailedReviewStopsWithoutEndlessRepair() async throws {
        var replies = [#"{"steps":["整理"]}"#, "原答复",
            #"{"passed":false,"issues":["遗漏约束"]}"#, "修正答复",
            #"{"passed":false,"issues":["仍缺少依据"]}"#]
        let engine = NexusReasoningEngine(tools: registry(), model: { _ in replies.removeFirst() })
        let result = try await engine.run(goal: "整理方案")
        XCTAssertFalse(result.reviewPassed)
        XCTAssertTrue(result.warning?.contains("仍缺少依据") == true)
        XCTAssertEqual(engine.modelCalls, 5)
        XCTAssertEqual(engine.plan?.steps.count, 2)
    }

    func testRepairCannotExceedSharedBudgetOrDiscardOriginalAnswer() async throws {
        var replies = [#"{"steps":["计算"]}"#, "尚待验证的答复",
            #"{"passed":false,"issues":["需要计算"]}"#,
            #"{"name":"calc","arguments":{"expression":"12*3"}}"#,
            #"{"name":"calc","arguments":{"expression":"12*4"}}"#]
        let engine = NexusReasoningEngine(tools: registry(), maxCalls: 5, model: { _ in replies.removeFirst() })
        let result = try await engine.run(goal: "计算")
        XCTAssertFalse(result.reviewPassed)
        XCTAssertEqual(result.text, "尚待验证的答复")
        XCTAssertTrue(result.warning?.contains("上限") == true)
        XCTAssertEqual(engine.modelCalls, 5)
        XCTAssertEqual(engine.plan?.steps.last?.status, .failed)
    }

    func testInsufficientBudgetDoesNotStartRepair() async throws {
        var replies = [#"{"steps":["计算"]}"#, "原答复",
            #"{"passed":false,"issues":["缺少证据"]}"#]
        let engine = NexusReasoningEngine(tools: registry(), maxCalls: 4, model: { _ in replies.removeFirst() })
        let result = try await engine.run(goal: "计算")
        XCTAssertFalse(result.reviewPassed)
        XCTAssertEqual(engine.modelCalls, 3)
        XCTAssertEqual(engine.plan?.steps.count, 1)
        XCTAssertTrue(result.warning?.contains("额度不足") == true)
    }

    func testCancellationDuringRepairCannotPassOrContinueReview() async throws {
        let reachedRepair = expectation(description: "reached repair")
        var calls = 0
        let engine = NexusReasoningEngine(tools: registry(), model: { _ in
            calls += 1
            switch calls {
            case 1: return #"{"steps":["计算"]}"#
            case 2: return "原答复"
            case 3: return #"{"passed":false,"issues":["需要验证"]}"#
            default:
                reachedRepair.fulfill()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return "不得返回"
            }
        })
        let task = Task { try await engine.run(goal: "计算") }
        await fulfillment(of: [reachedRepair], timeout: 3)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled repair must propagate cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls, 4)
        XCTAssertEqual(engine.plan?.steps.last?.status, .skipped)
    }
}
