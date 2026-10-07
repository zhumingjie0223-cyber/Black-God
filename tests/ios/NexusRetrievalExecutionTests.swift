import Foundation
import XCTest
@testable import BlackGod

private struct MalformedMemoryRetrievalTool: NexusTool {
    let name = "memory_search"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        .init(callID: call.id, output: "not-a-candidate-list", succeeded: true)
    }
}

@MainActor
final class NexusRetrievalExecutionTests: XCTestCase {
    private func engine(tools: NexusToolRegistry, requests: @escaping (String) -> Void) -> NexusReasoningEngine {
        var executionRequests = 0
        return NexusReasoningEngine(tools: tools, model: { prompt in
            requests(prompt)
            if prompt.contains("[任务规划]") { return #"{"steps":["检索已核对的用户记忆"]}"# }
            if prompt.contains("[结果复核]") {
                XCTFail("空检索结果不能再让模型自评通过")
                return #"{"passed":true,"issues":[]}"#
            }
            executionRequests += 1
            if executionRequests == 1 { return #"{"name":"memory_search","arguments":{"query":"饮食偏好"}}"# }
            return "你偏好甜咖啡、海鲜和夜宵，这是已确认的个人偏好。"
        })
    }

    func testActualEmptyMemorySearchReturnsProgramMessageInsteadOfInventedPreferences() async throws {
        var tools = NexusToolRegistry()
        tools.register(NexusMemorySearchTool(items: []))
        var requests: [String] = []
        let engine = engine(tools: tools, requests: { requests.append($0) })
        let outcome = try await engine.run(goal: "查找我的饮食偏好")
        XCTAssertEqual(engine.intentCard?.preferredTool, "memory_search")
        XCTAssertEqual(engine.executor?.toolTraces.count, 1)
        XCTAssertEqual(engine.executor?.toolTraces.first?.succeeded, true)
        XCTAssertEqual(requests.count, 3)
        XCTAssertFalse(requests.contains { $0.contains("[结果复核]") })
        XCTAssertFalse(outcome.reviewPassed)
        XCTAssertNil(outcome.warning)
        XCTAssertEqual(outcome.text, "没有检索到相关用户记录；目前没有依据判断你的偏好或补充用户事实。")
        XCTAssertFalse(outcome.text.contains("甜咖啡"))
    }

    func testMalformedRetrievalCannotBecomeObservedUserFactEvenWhenToolSaysSuccess() async throws {
        var tools = NexusToolRegistry()
        tools.register(MalformedMemoryRetrievalTool())
        var requests: [String] = []
        let engine = engine(tools: tools, requests: { requests.append($0) })
        let outcome = try await engine.run(goal: "查找我的饮食偏好")
        XCTAssertEqual(engine.executor?.toolTraces.first?.succeeded, true)
        XCTAssertEqual(requests.count, 3)
        XCTAssertFalse(outcome.reviewPassed)
        XCTAssertTrue(outcome.warning?.contains("检索输出缺少可核对") == true)
        XCTAssertTrue(outcome.text.contains("没有依据判断你的偏好"))
        XCTAssertFalse(outcome.text.contains("甜咖啡"))
    }
}
