import Foundation
import XCTest
@testable import BlackGodCore

private struct PortablePlanner: NexusPlanning {
    func makePlan(for goal: String) -> NexusTaskPlan {
        .init(id: UUID(), goal: goal, steps: [.init(title: "执行任务")], createdAt: Date())
    }
}

private actor PortableExecutions {
    private(set) var calls: [NexusToolCall] = []
    func record(_ call: NexusToolCall) { calls.append(call) }
}

private struct PortableCountingTool: NexusTool {
    let name: String
    let executions: PortableExecutions
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        await executions.record(call)
        return .init(callID: call.id, output: "操作返回证据", succeeded: true)
    }
}

@MainActor
final class PortableExecutionTests: XCTestCase {
    func testCalculatorRejectsInvalidInputsAndChecksRealArithmetic() async {
        for expression in ["", "1/0", "1+", "NaN", "0;rm", String(repeating: "(", count: 65) + "1"] {
            let result = await NexusCalculatorTool().execute(.init(id: UUID(), name: "calc", arguments: ["expression": expression]))
            XCTAssertFalse(result.succeeded, expression)
        }
        let result = await NexusCalculatorTool().execute(.init(id: UUID(), name: "calc", arguments: ["expression": "(12*3)+4/2"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(Double(result.output), 38)
    }

    func testFailedCheckpointPreventsLegacyToolSideEffect() async {
        let executions = PortableExecutions()
        var registry = NexusToolRegistry()
        registry.register(PortableCountingTool(name: "calc", executions: executions))
        let executor = NexusExecutor(planner: PortablePlanner(), verifier: NexusContentVerifier(),
            model: { _ in #"{"name":"calc","arguments":{"expression":"1+1"}}"# },
            tools: registry, onCheckpoint: { _, _, pending in
                if pending != nil { throw PortableAdapterError.unavailable }
            })
        let output = await executor.run(goal: "计算1+1")
        XCTAssertEqual(output, "")
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(executor.lastError?.contains("保存任务进度失败") == true)
    }

    func testFailedCheckpointPreventsNativeToolSideEffect() async {
        let executions = PortableExecutions()
        var registry = NexusToolRegistry()
        registry.register(PortableCountingTool(name: "calc", executions: executions))
        let executor = NexusExecutor(planner: PortablePlanner(), verifier: NexusContentVerifier(), tools: registry,
            nativeTurn: { _, _ in
                .init(text: "", calls: [.init(providerID: "call_opaque", call: .init(id: UUID(), name: "calc", arguments: ["expression": "1+1"]))], assistant: [:])
            }, onCheckpoint: { _, _, pending in
                if pending != nil { throw PortableAdapterError.unavailable }
            })
        let output = await executor.run(goal: "计算1+1")
        XCTAssertEqual(output, "")
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(executor.lastError?.contains("保存任务进度失败") == true)
    }

    func testRepairUsesPreviousEvidenceWithoutRepeatingSuccessfulAction() async {
        let executions = PortableExecutions()
        var registry = NexusToolRegistry()
        registry.register(PortableCountingTool(name: "workspace_write", executions: executions))
        var prompts: [String] = []
        let executor = NexusExecutor(planner: PortablePlanner(), verifier: NexusContentVerifier(), model: { prompt in
            prompts.append(prompt)
            if prompts.count == 1 { return #"{"name":"workspace_write","arguments":{"path":"report.txt","content":"结果"}}"# }
            if prompts.count == 2 { return "报告已写入" }
            XCTAssertTrue(prompt.contains("操作返回证据"))
            XCTAssertTrue(prompt.contains("不要因为复核失败就重做原计划"))
            return "已保存报告，依据工作区返回结果。"
        }, tools: registry)
        _ = await executor.run(goal: "保存report.txt")
        let result = await executor.repair(goal: "保存report.txt", issues: ["说明证据"], answer: "报告已写入", criteria: ["保存报告"])
        let calls = await executions.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(executor.toolTraces.count, 1)
        XCTAssertTrue(result.contains("依据工作区返回结果"))
    }

    func testNativeSchemaRejectsUnexpectedArgumentBeforeExecution() async {
        let executions = PortableExecutions()
        var registry = NexusToolRegistry()
        registry.register(PortableCountingTool(name: "calc", executions: executions))
        var round = 0
        let executor = NexusExecutor(planner: PortablePlanner(), verifier: NexusContentVerifier(), tools: registry,
            nativeTurn: { messages, _ in
                round += 1
                if round == 1 {
                    return .init(text: "", calls: [.init(providerID: "unsafe", call: .init(id: UUID(), name: "calc", arguments: ["expression": "1+1", "extra": "unsafe"]))], assistant: [:])
                }
                guard case .results(let results) = messages.last else { throw NexusError.invalidResponse }
                XCTAssertFalse(results[0].1.succeeded)
                return .init(text: "参数被拒绝，尚未执行。", calls: [], assistant: [:])
            })
        _ = await executor.run(goal: "计算1+1")
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(executor.toolTraces.count, 1)
        XCTAssertFalse(executor.toolTraces[0].succeeded)
    }
}
