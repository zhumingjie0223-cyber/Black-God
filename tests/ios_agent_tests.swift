import Foundation

private struct AgentFixturePlanner: NexusPlanning {
    let titles: [String]
    func makePlan(for goal: String) -> NexusTaskPlan {
        NexusTaskPlan(id: UUID(), goal: goal, steps: titles.map {
            NexusTaskStep(title: $0, instruction: "完成 \($0)", acceptanceCriteria: ["输出 \($0) 的具体内容"])
        }, createdAt: Date())
    }
}

extension RuntimeRegressionTests {
    static func planningJSON(_ titles: [String]) -> String {
        let steps = titles.map { ["title": $0, "instruction": "执行 \($0)", "acceptanceCriteria": ["交付 \($0)"]] as [String: Any] }
        let data = try! JSONSerialization.data(withJSONObject: ["steps": steps])
        return String(decoding: data, as: UTF8.self)
    }

    static func testAgentPlanningAndVerification() {
        let raw = planningJSON(["列出约束", "比较方案", "给出实施清单"])
        let plan = NexusModelPlanning.parse(raw, goal: "规划")
        expect(plan?.steps.count == 3 && plan?.steps[1].instruction == "执行 比较方案", "specific plan preserves instructions")
        expect(plan?.steps.last?.acceptanceCriteria == ["交付 给出实施清单"], "plan preserves acceptance criteria")
        expect(NexusModelPlanning.parse(planningJSON([]), goal: "x") == nil, "empty plan rejected")
        expect(NexusModelPlanning.parse(planningJSON(Array(repeating: "step", count: 6)), goal: "x") == nil, "more than five steps rejected")
        expect(NexusModelPlanning.parse("```json\n\(raw)\n```", goal: "x") == nil, "planning requires strict raw JSON")
        expect(NexusModelPlanning.parse(#"{"steps":[{"title":"x","instruction":"x","acceptanceCriteria":["x"],"extra":true}]}"#, goal: "x") == nil, "unknown plan fields rejected")
        expect(NexusModelPlanning.parse(#"{"steps":[{"title":"x","instruction":"x","acceptanceCriteria":[]}]}"#, goal: "x") == nil, "missing acceptance rejected")
        expect(NexusModelPlanning.parse(planningJSON([String(repeating: "x", count: 81)]), goal: "x") == nil, "oversized title rejected")
        expect(BasicNexusPlanner().makePlan(for: "普通问题").steps.count == 1, "offline fallback is one direct step")

        let verifier = BasicNexusVerifier()
        for output in ["抱歉，我无法协助该请求，但可以介绍安全替代方案。", "I cannot determine that from the evidence.", "The error is caused by a timeout.", "无关但完整的内容"] {
            expect(verifier.verify(goal: "完全不同的目标关键词", output: output).passed, "structural check does not judge refusal, keywords or truth")
        }
        expect(verifier.verify(goal: "x", output: "some content").reason.contains("不代表事实正确"), "verification limitation is explicit")
        expect(verifier.verify(goal: "用一个表情回复", output: "👍").passed, "emoji-only answer is valid content")
        expect(!verifier.verify(goal: "x", output: "```swift\nlet x = 1").passed, "incomplete code fence rejected")
        expect(verifier.verify(goal: "x", output: "```swift\nlet x = 1\n```").passed, "complete code accepted")
        expect(!verifier.verify(goal: "x", output: " \n ").passed, "empty output rejected")
        expect(!verifier.verify(goal: "x", output: #"{"name":"echo","arguments":{"text":"x"}}"#).passed, "pending tool call is not final output")
        expect(!verifier.verify(goal: "x", output: String(repeating: "x", count: 12001)).passed, "oversized final output rejected")
    }

    static func testAdvancedExecutor() async throws {
        var prompts: [String] = []
        var updates: [[NexusStepStatus]] = []
        let planned = NexusExecutor(model: { prompt in
            prompts.append(prompt)
            switch prompts.count {
            case 1: return planningJSON(["约束", "方案", "最终交付"])
            case 2: return "prior-one-constraints"
            case 3: return "prior-two-options"
            default: return "Final deliverable"
            }
        }, onUpdate: { plan, _ in updates.append(plan.steps.map(\.status)) })
        expect(awaitValue: await planned.run(goal: "设计方案"), equals: "Final deliverable", "only final delivery is returned")
        expect(prompts.count == 4 && planned.modelCallCount == 4, "planning counts toward total model calls")
        expect(prompts[3].contains("prior-one-constraints") && prompts[3].contains("prior-two-options"), "all previous results reach final step")
        expect(prompts[2].contains("执行 方案") && prompts[2].contains("交付 方案"), "instructions and acceptance reach execution prompt")
        expect(updates.contains(where: { $0.contains(.running) }) && updates.last == [.passed, .passed, .passed], "UI receives incremental plan status")
        expect(planned.lastError == nil, "successful plan has no last error")

        var fallbackCalls = 0
        let fallback = NexusExecutor(model: { _ in
            fallbackCalls += 1
            return fallbackCalls == 1 ? "invalid planning JSON" : "Direct answer"
        })
        expect(awaitValue: await fallback.run(goal: "简单问题"), equals: "Direct answer", "invalid plan falls back safely")
        expect(fallback.plan?.steps.count == 1 && fallbackCalls == 2, "fallback does not repeat three generic stages")

        var refusedCalls = 0
        let refusal = NexusExecutor(planner: BasicNexusPlanner(), model: { prompt in
            refusedCalls += 1
            expect(!prompt.contains("不要以“抱歉") && !prompt.contains("覆盖目标中的关键词"), "no refusal override instruction")
            return "抱歉，我不能完成该请求，可以提供安全替代信息。"
        })
        let refusalResult = await refusal.run(goal: "request")
        expect(refusalResult.hasPrefix("抱歉") && refusedCalls == 1, "legitimate refusal is returned without coercive retry")

        var repairCalls = 0
        let repair = NexusExecutor(planner: BasicNexusPlanner(), model: { _ in
            repairCalls += 1
            return repairCalls == 1 ? "```swift\nlet x = 1" : "```swift\nlet x = 1\n```"
        })
        let repaired = await repair.run(goal: "code")
        expect(repaired.hasSuffix("```") && repairCalls == 2 && repair.verdicts.count == 2, "structural damage gets one bounded repair")

        let capped = NexusExecutor(planner: AgentFixturePlanner(titles: ["a", "b", "c"]), model: { _ in "done" }, limits: NexusExecutionLimits(maxModelCalls: 2))
        expect(awaitValue: await capped.run(goal: "task"), equals: "", "model budget never presents partial work as final")
        expect(capped.modelCallCount == 2 && capped.plan?.steps.map(\.status) == [.passed, .passed, .failed], "model cap preserves completed steps accurately")
        expect(capped.lastError?.contains("模型调用上限") == true, "model limit has actionable error")
        var resumedBudgetCalls = 0
        let stillCapped = NexusExecutor(model: { _ in resumedBudgetCalls += 1; return "wrong" }, limits: NexusExecutionLimits(maxModelCalls: 2))
        _ = await stillCapped.resume(checkpoint: capped.checkpoint!)
        expect(resumedBudgetCalls == 0 && stillCapped.modelCallCount == 2, "resume does not reset an exhausted model budget")

        var toolRequests = 0
        let toolCap = NexusExecutor(planner: BasicNexusPlanner(), model: { _ in
            toolRequests += 1
            return "{\"name\":\"echo\",\"arguments\":{\"text\":\"\(toolRequests)\"}}"
        }, limits: NexusExecutionLimits(maxToolCalls: 1))
        expect(awaitValue: await toolCap.run(goal: "task"), equals: "", "tool cap stops further execution")
        expect(toolCap.toolCallCount == 1 && toolCap.toolTraces.count == 1, "tool count is bounded")

        let batchCap = NexusExecutor(planner: BasicNexusPlanner(), model: { _ in
            "[" + Array(repeating: #"{"name":"echo","arguments":{"text":"x"}}"#, count: 5).joined(separator: ",") + "]"
        })
        _ = await batchCap.run(goal: "task")
        expect(batchCap.toolCallCount == 0 && batchCap.lastError != nil, "oversized batch executes no tools")

        var inputCalls = 0
        let inputCap = NexusExecutor(model: { _ in inputCalls += 1; return "x" }, limits: NexusExecutionLimits(maxGoalCharacters: 3))
        _ = await inputCap.run(goal: "1234")
        expect(inputCalls == 0 && inputCap.lastError != nil, "oversized user input makes no model call")
        let promptCap = NexusExecutor(planner: BasicNexusPlanner(), model: { _ in "x" }, limits: NexusExecutionLimits(maxPromptCharacters: 10))
        _ = await promptCap.run(goal: "x")
        expect(promptCap.modelCallCount == 0 && promptCap.lastError?.contains("上下文长度") == true, "prompt overflow stops without dropping prior results")
        let outputCap = NexusExecutor(planner: BasicNexusPlanner(), model: { _ in "1234" }, limits: NexusExecutionLimits(maxOutputCharacters: 3))
        _ = await outputCap.run(goal: "x")
        expect(outputCap.modelCallCount == 1 && outputCap.lastError?.contains("输出超过") == true, "model output size enforced")

        try await testResumeAndInterruption()
    }

    static func expect(awaitValue value: String, equals expected: String, _ message: String) { expect(value == expected, message) }

    static func testResumeAndInterruption() async throws {
        var requests = 0
        let original = NexusExecutor(planner: AgentFixturePlanner(titles: ["first", "second"]), model: { _ in
            requests += 1
            if requests == 1 { return "Saved first result" }
            throw FixtureError.network
        })
        expect(awaitValue: await original.run(goal: "task"), equals: "", "network failure does not masquerade as final answer")
        expect(original.plan?.steps.map(\.status) == [.passed, .interrupted], "network failure interrupts only active step")
        expect(requests == 2 && original.lastError?.contains("模型请求中断") == true, "network failure is not automatically retried")
        let saved = try JSONDecoder().decode(NexusCheckpoint.self, from: JSONEncoder().encode(original.checkpoint!))
        var resumedPrompts: [String] = []
        let resumed = NexusExecutor(model: { prompt in resumedPrompts.append(prompt); return "Resumed final" })
        expect(awaitValue: await resumed.resume(checkpoint: saved), equals: "Resumed final", "resume produces final output")
        expect(resumedPrompts.count == 1 && resumedPrompts[0].contains("Saved first result"), "completed step is reused without replanning or replay")
        expect(resumed.modelCallCount == 3 && resumed.lastError == nil, "resume preserves previous spend and clears recovered error")

        var unexpectedCalls = 0
        let alreadyComplete = NexusExecutor(model: { _ in unexpectedCalls += 1; return "wrong" })
        expect(awaitValue: await alreadyComplete.resume(checkpoint: resumed.checkpoint!), equals: "Resumed final", "completed checkpoint returns saved final")
        expect(unexpectedCalls == 0, "completed checkpoint makes zero model calls")

        var toolRequests = 0
        let interruptedTool = NexusExecutor(planner: BasicNexusPlanner(), model: { _ in
            toolRequests += 1
            if toolRequests == 1 { return #"{"name":"echo","arguments":{"text":"saved tool result"}}"# }
            throw FixtureError.network
        })
        _ = await interruptedTool.run(goal: "task")
        let toolCheckpoint = interruptedTool.checkpoint!
        var resumeToolCalls = 0
        let reuseTool = NexusExecutor(model: { prompt in
            resumeToolCalls += 1
            expect(prompt.contains("saved tool result"), "saved tool result included during resume")
            return resumeToolCalls == 1 ? #"{"name":"echo","arguments":{"text":"saved tool result"}}"# : "Final from tool"
        })
        _ = await reuseTool.resume(checkpoint: toolCheckpoint)
        expect(reuseTool.toolTraces.count == 1 && reuseTool.toolCallCount == 1, "same completed tool is not re-executed on resume")

        var started = false
        let cancellable = NexusExecutor(planner: AgentFixturePlanner(titles: ["first", "later"]), model: { _ in
            started = true
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return "must not finish"
        })
        let running = Task { await cancellable.run(goal: "task") }
        for _ in 0..<1000 {
            if started { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        expect(started, "cancellation fixture starts")
        running.cancel()
        expect(awaitValue: await running.value, equals: "", "cancelled run has no final success")
        expect(cancellable.plan?.steps.map(\.status) == [.interrupted, .pending], "cancelled and never-started statuses differ")
        expect(cancellable.lastError?.contains("已取消") == true, "cancellation is actionable")

        var preStartCalls = 0
        let preStart = NexusExecutor(model: { _ in preStartCalls += 1; return "wrong" })
        let preCancelled = Task { await preStart.run(goal: "task") }
        preCancelled.cancel()
        _ = await preCancelled.value
        expect(preStartCalls == 0 && preStart.modelCallCount == 0, "cancel before planning makes no model request")
        expect(preStart.plan?.steps.first?.status == .interrupted, "pre-start cancellation remains resumable")

        var planningFailureCalls = 0
        let planningFailure = NexusExecutor(model: { _ in planningFailureCalls += 1; throw FixtureError.network })
        _ = await planningFailure.run(goal: "task")
        expect(planningFailureCalls == 1 && planningFailure.plan?.steps.first?.status == .interrupted, "planning network failure stops with resumable direct plan")

        let legacyID = UUID(), legacyStepID = UUID()
        let legacy = "{\"plan\":{\"id\":\"\(legacyID)\",\"goal\":\"old\",\"steps\":[{\"id\":\"\(legacyStepID)\",\"title\":\"old step\",\"status\":\"pending\"}],\"createdAt\":0},\"observations\":[],\"verdicts\":[],\"savedAt\":0}"
        let decoded = try JSONDecoder().decode(NexusCheckpoint.self, from: Data(legacy.utf8))
        expect(decoded.plan.steps[0].instruction == "old step" && decoded.toolTraces == nil, "legacy checkpoint fields get compatible defaults")
        let legacyExecutor = NexusExecutor(model: { _ in "Legacy resumed" })
        expect(awaitValue: await legacyExecutor.resume(checkpoint: decoded), equals: "Legacy resumed", "legacy pending checkpoint resumes")

        let overBudget = NexusCheckpoint(plan: saved.plan, observations: [], verdicts: [], savedAt: Date(), modelCallCount: 100)
        let invalid = NexusExecutor(model: { _ in fatalError("invalid checkpoint must not call model") })
        _ = await invalid.resume(checkpoint: overBudget)
        expect(invalid.lastError?.contains("检查点") == true, "invalid checkpoint budget is rejected")

        let corruptPlan = NexusTaskPlan(id: UUID(), goal: "task", steps: [NexusTaskStep(title: "fake completed", status: .passed)], createdAt: Date())
        let corrupt = NexusCheckpoint(plan: corruptPlan, observations: [], verdicts: [], savedAt: Date())
        _ = await invalid.resume(checkpoint: corrupt)
        expect(invalid.lastError?.contains("检查点") == true, "completed step with missing result cannot be trusted")
    }
}
