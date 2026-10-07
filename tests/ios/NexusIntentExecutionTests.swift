import Foundation
import XCTest
@testable import BlackGod

private actor IntentExecutions {
    private(set) var calls: [NexusToolCall] = []
    func record(_ call: NexusToolCall) { calls.append(call) }
}

private struct IntentObservedTool: NexusTool {
    let name: String
    let executions: IntentExecutions
    var output = "金边报告内容：预算已核对。"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        await executions.record(call)
        return .init(callID: call.id, output: output, succeeded: true)
    }
}

@MainActor
final class NexusIntentExecutionTests: XCTestCase {
    private func file(_ id: String, title: String = "金边报告", path: String = "reports/phnom-penh.md") -> NexusRecallCandidate {
        .init(id: id, source: .workspaceFile, title: title, text: "工作区文件名", objectPath: path,
              provenance: "工作区目录", relevance: 0.9)
    }

    private func nativeReply(tool: String? = nil, arguments: [String: String] = [:], text: String = "") throws -> NexusNativeReply {
        var message: [String: Any] = ["role": "assistant", "content": text]
        if let tool {
            let input = try JSONSerialization.data(withJSONObject: arguments)
            message["tool_calls"] = [["id": UUID().uuidString, "type": "function",
                                       "function": ["name": tool, "arguments": String(decoding: input, as: UTF8.self)]]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": message, "finish_reason": tool == nil ? "stop" : "tool_calls"]]])
        return try NexusNativeCodec.decode(data, type: .openAICompatible)
    }

    func testAmbiguousDeletionAsksBeforeAnyModelOrToolRequest() async throws {
        let executions = IntentExecutions()
        var registry = NexusToolRegistry()
        registry.register(IntentObservedTool(name: "workspace_delete", executions: executions))
        let engine = NexusReasoningEngine(tools: registry, model: { _ in
            XCTFail("危险对象未消歧，不能进入模型计划")
            return "不应该执行"
        }, recall: { _ in [self.file("file:a"), self.file("file:b", title: "金边预算", path: "reports/budget.md")] }, intentModel: { _ in
            XCTFail("危险对象未消歧，不能交给分类模型猜测")
            return #"{"operation":"delete","objectID":"file:a"}"#
        })
        let result = try await engine.run(goal: "删掉那个")
        XCTAssertFalse(result.reviewPassed)
        XCTAssertTrue(result.text.contains("哪一个"))
        XCTAssertEqual(engine.modelCalls, 0)
        XCTAssertNil(engine.executor)
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testLowRiskPronounResolvesObjectThenUsesObservedToolEvidence() async throws {
        let executions = IntentExecutions()
        var registry = NexusToolRegistry()
        registry.register(IntentObservedTool(name: "workspace_read", executions: executions))
        var executionRequests = 0
        var events: [String] = []
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["核对报告"],"successCriteria":["读取目标文件"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            if executionRequests == 1 { return #"{"name":"workspace_read","arguments":{"path":"reports/phnom-penh.md"}}"# }
            return "金边报告预算已核对，依据工作区读取结果。"
        }, recall: { _ in [self.file("file:report")] }, onEvent: { events.append($0) })
        let result = try await engine.run(goal: "看看那个")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.intentCard?.objectID, "file:report")
        XCTAssertEqual(engine.executor?.toolTraces.count, 1)
        let calls = await executions.calls
        XCTAssertEqual(calls.map { $0.arguments["path"] }, ["reports/phnom-penh.md"])
        XCTAssertTrue(events.contains(where: { $0.contains("按金边报告") }) || result.text.contains("按金边报告"))
    }

    func testPlannerCannotReadDifferentObjectThanCompiledCard() async throws {
        let executions = IntentExecutions()
        var registry = NexusToolRegistry()
        registry.register(IntentObservedTool(name: "workspace_read", executions: executions))
        var executionRequests = 0
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["读取报告"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            if executionRequests == 1 { return #"{"name":"workspace_read","arguments":{"path":"reports/other.md"}}"# }
            return "不同对象的读取已被拦截；未完成读取。"
        }, recall: { _ in [self.file("file:report")] })
        let result = try await engine.run(goal: "读取金边报告")
        XCTAssertFalse(result.reviewPassed)
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(engine.executor?.toolTraces.contains(where: \.authorizationDenied) == true)
    }

    func testAmbiguousReadCannotEscalateToShell() async throws {
        let executions = IntentExecutions()
        var registry = NexusToolRegistry()
        registry.register(IntentObservedTool(name: "workspace_read", executions: executions))
        registry.register(IntentObservedTool(name: "shell_execute", executions: executions))
        var executionRequests = 0
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["处理报告"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            if executionRequests == 1 { return #"{"name":"shell_execute","arguments":{"command":"cat reports/phnom-penh.md"}}"# }
            return "终端调用已被拦截；尚未读取报告。"
        }, recall: { _ in [self.file("file:report")] })
        let result = try await engine.run(goal: "弄一下那个")
        XCTAssertFalse(result.reviewPassed)
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(engine.intentCard?.allowedTools.contains("shell_execute") ?? true)
        XCTAssertTrue(engine.executor?.toolTraces.contains(where: \.authorizationDenied) == true)
    }

    func testMandatoryIntentCompilationDoesNotExpandRequestBudget() async throws {
        var registry = NexusToolRegistry()
        registry.register(NexusCalculatorTool())
        let engine = NexusReasoningEngine(tools: registry, maxCalls: 1, model: { _ in #"{"steps":["计算"]}"# })
        do {
            _ = try await engine.run(goal: "计算12乘3")
            XCTFail("模型执行必须受总请求上限限制")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("上限"))
        }
        XCTAssertEqual(engine.modelCalls, 1)
        XCTAssertNotNil(engine.intentCard)
        XCTAssertTrue(engine.executor?.toolTraces.isEmpty ?? true)
    }

    func testIntentRoleClassifiesSlotsWhilePlanningAndReviewStayOnMainRole() async throws {
        let executions = IntentExecutions()
        var registry = NexusToolRegistry()
        registry.register(IntentObservedTool(name: "workspace_read", executions: executions))
        var intentRequests = 0
        var executionRequests = 0
        var planningRequests = 0
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            planningRequests += 1
            XCTAssertFalse(prompt.contains("[意图分类与槽填充]"))
            if prompt.contains("[任务规划]") { return #"{"steps":["读取已选对象"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            if executionRequests == 1 { return #"{"name":"workspace_read","arguments":{"path":"reports/budget.md"}}"# }
            return "报告预算已核对，依据工作区读取结果。"
        }, recall: { _ in [self.file("file:a"), self.file("file:b", title: "金边预算", path: "reports/budget.md")] }, intentModel: { prompt in
            intentRequests += 1
            XCTAssertTrue(prompt.contains("[意图分类与槽填充]"))
            XCTAssertFalse(prompt.contains("[任务规划]"))
            return #"{"operation":"inspect","objectID":"file:b","constraints":[]}"#
        })
        let result = try await engine.run(goal: "看看那个")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.intentCard?.objectID, "file:b")
        XCTAssertEqual(intentRequests, 1)
        XCTAssertEqual(planningRequests, 4)
        XCTAssertEqual(engine.modelCalls, intentRequests + planningRequests)
        let calls = await executions.calls
        XCTAssertEqual(calls.map { $0.arguments["path"] }, ["reports/budget.md"])
    }

    func testClassificationAndPlanningShareTheSameGlobalRequestBudget() async throws {
        var registry = NexusToolRegistry()
        registry.register(NexusCalculatorTool())
        var intentRequests = 0
        var planningRequests = 0
        let engine = NexusReasoningEngine(tools: registry, maxCalls: 2, model: { _ in
            planningRequests += 1
            return #"{"steps":["计算"]}"#
        }, intentModel: { _ in
            intentRequests += 1
            return #"{"operation":"calculate","objectID":null,"constraints":[]}"#
        })
        do {
            _ = try await engine.run(goal: "计算12乘3")
            XCTFail("分类与规划不能各自另开预算")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("上限"))
        }
        XCTAssertEqual(intentRequests, 1)
        XCTAssertEqual(planningRequests, 1)
        XCTAssertEqual(engine.modelCalls, 2)
        XCTAssertTrue(engine.executor?.toolTraces.isEmpty ?? true)
    }

    func testNativeSecondRoundRetainsIntentCardAndOnlyAdvertisesAuthorizedScope() async throws {
        let executions = IntentExecutions()
        var registry = NexusToolRegistry()
        for name in ["workspace_read", "workspace_delete", "shell_execute"] {
            registry.register(IntentObservedTool(name: name, executions: executions))
        }
        var nativeRounds = 0
        var observedCards: [NexusIntentCard] = []
        let expectedCard = NexusIntentCompiler.compile(goal: "读取金边报告", candidates: [file("file:report")], availableTools: Set(registry.nativeDefinitions.map(\.name)))
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["读取报告"]}"# }
            return #"{"passed":true,"issues":[]}"#
        }, recall: { _ in [self.file("file:report")] }, nativeTurn: { messages, definitions in
            nativeRounds += 1
            guard case .text(_, let first) = messages.first else { throw NexusError.invalidResponse }
            let cardJSON = try XCTUnwrap(first.split(separator: "\n").dropFirst().first)
            observedCards.append(try JSONDecoder().decode(NexusIntentCard.self, from: Data(cardJSON.utf8)))
            XCTAssertTrue(first.contains("[本地意图任务卡"))
            XCTAssertTrue(first.contains("file:report"))
            XCTAssertTrue(first.contains("reports/phnom-penh.md"))
            XCTAssertEqual(Set(definitions.map(\.name)), expectedCard.allowedTools)
            XCTAssertFalse(definitions.contains { ["workspace_delete", "shell_execute"].contains($0.name) })
            if nativeRounds == 1 {
                return try self.nativeReply(tool: "workspace_read", arguments: ["path": "reports/phnom-penh.md"])
            }
            guard case .results(let results) = messages.last else { throw NexusError.invalidResponse }
            XCTAssertEqual(results.first?.0.call.arguments["path"], "reports/phnom-penh.md")
            XCTAssertEqual(results.first?.1.succeeded, true)
            return try self.nativeReply(text: "金边报告预算已核对，依据工作区读取结果。")
        })
        let result = try await engine.run(goal: "读取金边报告")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(nativeRounds, 2)
        XCTAssertEqual(observedCards, [expectedCard, expectedCard])
        let calls = await executions.calls
        XCTAssertEqual(calls.map(\.name), ["workspace_read"])
    }

    func testCancelAndNewTaskDoNotInheritPendingDeletion() async throws {
        let executions = IntentExecutions()
        var registry = NexusToolRegistry()
        registry.register(IntentObservedTool(name: "workspace_delete", executions: executions))
        registry.register(NexusCalculatorTool())
        let candidates = [file("file:a"), file("file:b", title: "金边预算", path: "reports/budget.md")]
        let pending = NexusIntentCompiler.compile(goal: "删掉那个", candidates: candidates, availableTools: Set(registry.nativeDefinitions.map(\.name)))
        XCTAssertTrue(pending.missingSlots.contains("object"))
        for reply in ["取消", "计算2+2"] {
            var executionRequests = 0
            let engine = NexusReasoningEngine(tools: registry, model: { prompt in
                if prompt.contains("[任务规划]") {
                    return reply == "取消" ? #"{"answer":"已取消这次任务。"}"# : #"{"steps":["计算"]}"#
                }
                if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
                executionRequests += 1
                return executionRequests == 1 ? #"{"name":"calc","arguments":{"expression":"2+2"}}"# : "计算结果是4。"
            }, recall: { _ in candidates }, pendingIntent: pending)
            let result = try await engine.run(goal: reply)
            XCTAssertFalse(engine.intentCard?.allowedTools.contains("workspace_delete") ?? true)
            XCTAssertNotEqual(engine.intentCard?.operation, .delete)
            XCTAssertEqual(engine.intentCard?.goal, reply)
            XCTAssertFalse(result.requiresClarification)
            if reply == "取消" { XCTAssertNil(engine.executor) }
            else {
                XCTAssertTrue(result.reviewPassed)
                XCTAssertEqual(engine.executor?.toolTraces.map { $0.call.name }, ["calc"])
            }
        }
        let calls = await executions.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testObjectClarificationPreservesDeletionAndIncludesOriginalGoalInRecall() async throws {
        let executions = IntentExecutions()
        var registry = NexusToolRegistry()
        registry.register(IntentObservedTool(name: "workspace_delete", executions: executions, output: "已删除 reports/budget.md"))
        let candidates = [file("file:a"), file("file:b", title: "金边预算", path: "reports/budget.md")]
        let pending = NexusIntentCompiler.compile(goal: "删掉那个", candidates: candidates, availableTools: Set(registry.nativeDefinitions.map(\.name)))
        var recallQueries: [String] = []
        var executionRequests = 0
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["删除指定预算"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            return executionRequests == 1 ? #"{"name":"workspace_delete","arguments":{"path":"reports/budget.md","confirm":"确认删除"}}"# : "已删除金边预算，依据删除工具返回结果。"
        }, recall: { query in recallQueries.append(query); return candidates }, intentModel: { _ in
            XCTFail("原危险任务补槽不能重新交分类模型选择动作")
            return "{}"
        }, pendingIntent: pending)
        let result = try await engine.run(goal: "金边预算")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(recallQueries, ["删掉那个\n金边预算"])
        XCTAssertEqual(engine.intentCard?.goal, "删掉那个")
        XCTAssertEqual(engine.intentCard?.operation, .delete)
        XCTAssertEqual(engine.intentCard?.objectID, "file:b")
        XCTAssertEqual(engine.intentCard?.objectPath, "reports/budget.md")
        XCTAssertTrue(engine.executor?.sourceEvidence.contains { $0.id == "user:clarification" } == true)
        let calls = await executions.calls
        XCTAssertEqual(calls.map(\.name), ["workspace_delete"])
        XCTAssertEqual(calls.map { $0.arguments["path"] }, ["reports/budget.md"])
    }

    func testOptionalClassifierNetworkFailureUsesLocalCardAndStillConsumesBudget() async throws {
        var registry = NexusToolRegistry()
        registry.register(NexusCalculatorTool())
        var intentRequests = 0
        var mainRequests = 0
        var executionRequests = 0
        var events: [String] = []
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            mainRequests += 1
            if prompt.contains("[任务规划]") { return #"{"steps":["计算"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            return executionRequests == 1 ? #"{"name":"calc","arguments":{"expression":"12*3"}}"# : "计算结果是36。"
        }, intentModel: { _ in
            intentRequests += 1
            throw URLError(.cannotConnectToHost)
        }, onEvent: { events.append($0) })
        let result = try await engine.run(goal: "计算12乘3")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.intentCard?.operation, .calculate)
        XCTAssertEqual(intentRequests, 1)
        XCTAssertEqual(mainRequests, 4)
        XCTAssertEqual(engine.modelCalls, intentRequests + mainRequests)
        XCTAssertEqual(engine.executor?.toolTraces.map { $0.call.name }, ["calc"])
        XCTAssertTrue(events.contains { $0.contains("继续使用本地意图卡") })
    }

    func testOversizedRequestSettingStillClampsTaskToTwentyCalls() async throws {
        var registry = NexusToolRegistry()
        registry.register(NexusCalculatorTool())
        var mainRequests = 0
        var nativeRequests = 0
        var intentRequests = 0
        let engine = NexusReasoningEngine(tools: registry, maxCalls: 99, model: { prompt in
            mainRequests += 1
            if prompt.contains("[任务规划]") { return #"{"steps":["甲","乙","丙","丁","不能进入第五步"]}"# }
            if prompt.contains("[结果汇总]") { return "计算结果是36。" }
            return #"{"passed":false,"issues":["需要修正答复措辞"]}"#
        }, intentModel: { _ in
            intentRequests += 1
            return #"{"operation":"calculate","constraints":[]}"#
        }, nativeTurn: { _, _ in
            nativeRequests += 1
            if nativeRequests <= 16, nativeRequests % 4 != 0 {
                return try self.nativeReply(tool: "calc", arguments: ["expression": "12*3"])
            }
            return try self.nativeReply(text: "计算结果是36。")
        })
        let result = try await engine.run(goal: "计算12乘3")
        XCTAssertFalse(result.reviewPassed)
        XCTAssertEqual(engine.plan?.steps.count, 4)
        XCTAssertEqual(mainRequests, 3)
        XCTAssertEqual(nativeRequests, 16)
        XCTAssertEqual(intentRequests, 1)
        XCTAssertEqual(engine.modelCalls, 20)
        XCTAssertEqual(engine.modelCalls, mainRequests + nativeRequests + intentRequests)
        XCTAssertTrue(result.warning?.contains("剩余请求额度不足") == true)
    }

    func testLegacyCheckpointDecodesWithNoContinuationSeedOrSourceID() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NexusAgentCheckpointStore(url: folder.appendingPathComponent("legacy.agent.json"))
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "旧版本任务", connection: NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel))
        saved.state = .interrupted
        saved.sourceID = "new-field-not-in-legacy"
        _ = try store.save(saved)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
        for key in ["clarificationIntent", "sourceID", "intentCard", "needsClarification"] { legacy.removeValue(forKey: key) }
        try JSONSerialization.data(withJSONObject: legacy).write(to: store.url)
        let reloaded = try XCTUnwrap(store.load())
        XCTAssertEqual(reloaded.id, saved.id)
        XCTAssertEqual(reloaded.goal, "旧版本任务")
        XCTAssertEqual(reloaded.state, .interrupted)
        XCTAssertTrue(reloaded.canResume)
        XCTAssertNil(reloaded.clarificationIntent)
        XCTAssertNil(reloaded.sourceID)
        XCTAssertNil(reloaded.intentCard)
        XCTAssertNil(reloaded.needsClarification)
    }

    func testPersistedContinuationSeedSurvivesProgressAndResumesOriginalDeletionScope() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let executions = IntentExecutions()
        var registry = NexusToolRegistry()
        registry.register(IntentObservedTool(name: "workspace_delete", executions: executions, output: "已删除 reports/budget.md"))
        let candidates = [file("file:a"), file("file:b", title: "金边预算", path: "reports/budget.md")]
        let available = Set(registry.nativeDefinitions.map(\.name))
        let seed = NexusIntentCompiler.compile(goal: "删掉那个", candidates: candidates, availableTools: available)
        let resolved = try XCTUnwrap(NexusIntentCompiler.compileContinuation(pending: seed, reply: "金边预算", candidates: candidates, availableTools: available))
        var saved = NexusAgentCheckpoint(id: UUID(), goal: "金边预算", connection: NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel))
        saved.clarificationIntent = seed
        saved.sourceID = "shortcut:fixture"
        saved.update(NexusAgentProgress(plan: NexusTaskPlan(id: UUID(), goal: resolved.resolvedGoal,
            steps: [NexusTaskStep(title: "删除指定对象")], createdAt: Date()), criteria: resolved.successCriteria,
            traces: [], pendingTool: "workspace_delete", intentCard: resolved))
        saved.state = .interrupted
        let store = NexusAgentCheckpointStore(url: folder.appendingPathComponent("clarified.agent.json"))
        _ = try store.save(saved)
        let reloaded = try XCTUnwrap(store.load())
        XCTAssertEqual(reloaded.clarificationIntent, seed)
        XCTAssertEqual(reloaded.intentCard, resolved)
        XCTAssertEqual(reloaded.sourceID, "shortcut:fixture")
        XCTAssertEqual(reloaded.goal, "金边预算")
        var executionRequests = 0
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            if prompt.contains("[任务规划]") { return #"{"steps":["删除指定预算"]}"# }
            if prompt.contains("[结果复核]") { return #"{"passed":true,"issues":[]}"# }
            executionRequests += 1
            return executionRequests == 1 ? #"{"name":"workspace_delete","arguments":{"path":"reports/budget.md","confirm":"确认删除"}}"# : "已删除金边预算，依据删除工具返回结果。"
        }, recall: { query in
            XCTAssertEqual(query, "删掉那个\n金边预算")
            return candidates
        }, pendingIntent: reloaded.clarificationIntent)
        let result = try await engine.run(goal: reloaded.goal)
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.intentCard?.operation, .delete)
        XCTAssertEqual(engine.intentCard?.goal, "删掉那个")
        XCTAssertEqual(engine.intentCard?.objectID, "file:b")
        XCTAssertEqual(engine.intentCard?.objectPath, "reports/budget.md")
        XCTAssertFalse(engine.intentCard?.permits(tool: "workspace_delete", arguments: ["path": "reports/phnom-penh.md"]) ?? true)
        let calls = await executions.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.arguments["path"], "reports/budget.md")
    }
}
