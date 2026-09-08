// ios-app/NexusExecutor.swift
import Foundation

// MARK: - 工具调用记录与错误

struct NexusToolTrace: Codable, Equatable {
    let stepID: NexusTaskStep.ID
    let round: Int
    let call: NexusToolCall
    let result: String
    let succeeded: Bool
    let timestamp: Date
}

enum NexusToolError: LocalizedError {
    case unknownTool(String)
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "未知工具：\(name)"
        case .invalidArguments(let detail): return "参数无效：\(detail)"
        }
    }
}

// MARK: - 内置工具（只读安全，供 Executor 闭环默认装载）

struct NexusClockTool: NexusTool {
    let name = "clock"
    let usage = "获取当前日期时间。参数：timezone=可选时区标识（如 Asia/Shanghai）"

    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        let tzID = (call.arguments["timezone"] ?? call.arguments["tz"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !tzID.isEmpty, let tz = TimeZone(identifier: tzID) {
            formatter.timeZone = tz
        }
        return NexusToolResult(callID: call.id, output: formatter.string(from: Date()), succeeded: true)
    }
}

struct NexusCalculatorTool: NexusTool {
    let name = "calc"
    let usage = "计算数学表达式。参数：expr=表达式（如 (3+4)*2）"

    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        let expr = (call.arguments["expr"] ?? call.arguments["expression"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty else {
            return NexusToolResult(callID: call.id, output: "参数无效：表达式为空", succeeded: false)
        }
        guard let value = NexusArithmetic.evaluate(expr) else {
            return NexusToolResult(callID: call.id, output: "无法求值：\(expr)（仅支持数字与 + - * / ( )）", succeeded: false)
        }
        // 整数结果去掉多余小数
        if value == value.rounded(), abs(value) < 1e15 {
            return NexusToolResult(callID: call.id, output: String(Int64(value)), succeeded: true)
        }
        return NexusToolResult(callID: call.id, output: String(value), succeeded: true)
    }
}

/// 安全的四则运算求值器（递归下降），不使用 `NSExpression`，避免非法输入触发不可捕获的异常。
enum NexusArithmetic {
    static func evaluate(_ expression: String) -> Double? {
        guard expression.count <= 4096 else { return nil }
        var parser = Parser(Array(expression))
        guard let value = parser.parseExpression(), value.isFinite, parser.isAtEnd else { return nil }
        return value
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        var depth = 0
        init(_ chars: [Character]) { self.chars = chars }

        var isAtEnd: Bool { mutating get { skipSpaces(); return index >= chars.count } }

        mutating func skipSpaces() { while index < chars.count, chars[index].isWhitespace { index += 1 } }

        mutating func peek() -> Character? { skipSpaces(); return index < chars.count ? chars[index] : nil }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
                guard value.isFinite else { return nil }
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                index += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "/" { guard rhs != 0 else { return nil }; value /= rhs }
                else { value *= rhs }
                guard value.isFinite else { return nil }
            }
            return value
        }

        mutating func parseFactor() -> Double? {
            guard depth < 64 else { return nil }
            depth += 1
            defer { depth -= 1 }
            guard let ch = peek() else { return nil }
            if ch == "+" { index += 1; return parseFactor() }
            if ch == "-" { index += 1; guard let v = parseFactor() else { return nil }; return -v }
            if ch == "(" {
                index += 1
                guard let v = parseExpression(), peek() == ")" else { return nil }
                index += 1
                return v
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Double? {
            skipSpaces()
            var digits = ""
            while index < chars.count, chars[index].isNumber || chars[index] == "." {
                digits.append(chars[index]); index += 1
            }
            guard let value = Double(digits), value.isFinite else { return nil }
            return value
        }
    }
}

/// 本文件内使用的默认工具注册表构造函数（只读安全工具集）。
private func nexusExecutorDefaultToolRegistry() -> NexusToolRegistry {
    NexusToolRegistry([NexusClockTool(), NexusCalculatorTool(), EchoTool()])
}

// MARK: - 执行器

private enum NexusExecutionError: LocalizedError {
    case invalidInput, invalidCheckpoint, modelLimit, toolLimit, roundLimit, promptTooLarge, outputTooLarge, structure(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "任务为空或超过输入长度上限，请缩短后重试。"
        case .invalidCheckpoint: return "检查点内容不完整或超出执行限制，无法继续。"
        case .modelLimit: return "已达到本任务的模型调用上限，请使用已完成结果建立新任务。"
        case .toolLimit: return "已达到本任务的工具调用上限。"
        case .roundLimit: return "本步骤已达到工具轮次上限，模型尚未返回最终内容。"
        case .promptTooLarge: return "任务与前序结果超过上下文长度上限，请缩小任务范围。"
        case .outputTooLarge: return "模型输出超过单次长度上限，请缩小任务范围。"
        case .structure(let reason): return reason
        }
    }
}

@MainActor
final class NexusExecutor {
    typealias ModelCall = (String) async throws -> String

    private(set) var plan: NexusTaskPlan?
    private(set) var observations: [NexusObservation] = []
    private(set) var verdicts: [NexusVerdict] = []
    private(set) var toolTraces: [NexusToolTrace] = []
    private(set) var lastError: String?
    private(set) var modelCallCount = 0
    private(set) var toolCallCount = 0

    private let planner: NexusPlanning?
    private let verifier: NexusVerifying
    private let model: ModelCall
    private let tools: NexusToolRegistry
    private let maxToolRounds: Int
    private let limits: NexusExecutionLimits
    private let onEvent: ((String) -> Void)?
    private let onUpdate: ((NexusTaskPlan, [NexusToolTrace]) -> Void)?
    private var isRunning = false

    var checkpoint: NexusCheckpoint? {
        guard let plan else { return nil }
        return NexusCheckpoint(plan: plan, observations: observations, verdicts: verdicts, savedAt: Date(),
                               toolTraces: toolTraces, modelCallCount: modelCallCount,
                               toolCallCount: toolCallCount, lastError: lastError)
    }

    init(
        planner: NexusPlanning? = nil,
        verifier: NexusVerifying = BasicNexusVerifier(),
        model: @escaping ModelCall = { try await NexusModelBridge.complete($0) },
        tools: NexusToolRegistry = nexusExecutorDefaultToolRegistry(),
        maxToolRounds: Int = 4,
        limits: NexusExecutionLimits = NexusExecutionLimits(),
        onEvent: ((String) -> Void)? = nil,
        onUpdate: ((NexusTaskPlan, [NexusToolTrace]) -> Void)? = nil
    ) {
        self.planner = planner
        self.verifier = verifier
        self.model = model
        self.tools = tools
        self.maxToolRounds = min(4, max(1, maxToolRounds))
        self.limits = limits
        self.onEvent = onEvent
        self.onUpdate = onUpdate
    }

    func run(goal: String) async -> String {
        await execute(goal: goal, restoring: nil)
    }

    func resume(checkpoint: NexusCheckpoint) async -> String {
        await execute(goal: checkpoint.plan.goal, restoring: checkpoint)
    }

    private func execute(goal: String, restoring saved: NexusCheckpoint?) async -> String {
        guard !isRunning else { return "" }
        isRunning = true
        defer { isRunning = false }
        lastError = nil
        observations = []
        verdicts = []
        toolTraces = []
        modelCallCount = 0
        toolCallCount = 0
        plan = nil
        let goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        var currentIndex = 0

        do {
            guard NexusModelPlanning.valid(goal, maximum: limits.maxGoalCharacters) else {
                throw NexusExecutionError.invalidInput
            }
            if let saved {
                try restore(saved)
                onEvent?("已恢复任务；已完成步骤不会重复执行")
            } else {
                plan = (planner ?? BasicNexusPlanner()).makePlan(for: goal)
                try validatePlan()
                publish()
                if planner == nil {
                    onEvent?("正在生成具体任务步骤…")
                    let output = try await callModel(NexusModelPlanning.prompt(goal: goal, manifest: tools.manifest))
                    if let generated = NexusModelPlanning.parse(output, goal: goal) {
                        plan = generated
                    } else {
                        onEvent?("规划格式不完整，改为直接完成任务")
                    }
                }
                onEvent?("计划已生成：\(plan?.steps.count ?? 0) 步")
            }
            publish()
            try Task.checkCancellation()

            guard let stepCount = plan?.steps.count else { throw NexusExecutionError.invalidCheckpoint }
            for index in 0..<stepCount {
                currentIndex = index
                guard let step = plan?.steps[index] else { throw NexusExecutionError.invalidCheckpoint }
                if step.status == .passed { continue }
                try Task.checkCancellation()
                plan?.steps[index].status = .running
                plan?.steps[index].result = nil
                publish()
                onEvent?("开始步骤：\(step.title)")

                var output = ""
                var verdict = NexusVerdict(passed: false, reason: "尚未检查", checkedAt: Date())
                for attempt in 0..<2 {
                    output = try await runStep(index: index, previousReason: attempt == 0 ? nil : verdict.reason)
                    try Task.checkCancellation()
                    verdict = verifier.verify(goal: goal, output: output)
                    observations.append(NexusObservation(stepID: step.id, output: output, timestamp: Date()))
                    verdicts.append(verdict)
                    if verdict.passed { break }
                    if attempt == 0 { onEvent?("结果结构不完整，修复一次：\(verdict.reason)") }
                }
                guard verdict.passed else { throw NexusExecutionError.structure(verdict.reason) }
                plan?.steps[index].result = output
                plan?.steps[index].status = .passed
                publish()
                onEvent?("步骤完成：\(step.title)（仅检查结构完整性）")
            }
            guard let plan, plan.steps.allSatisfy({ $0.status == .passed }), let final = plan.steps.last?.result else {
                throw NexusExecutionError.invalidCheckpoint
            }
            onEvent?("执行完成；事实与实际任务成效仍需按内容核实")
            return final
        } catch {
            let interrupted = Task.isCancelled || error is CancellationError || !(error is NexusExecutionError)
            lastError = Task.isCancelled || error is CancellationError
                ? "任务已取消，可从检查点继续。"
                : (error is NexusExecutionError ? error.localizedDescription : "模型请求中断：\(error.localizedDescription)")
            if let steps = plan?.steps, steps.indices.contains(currentIndex), steps[currentIndex].status != .passed {
                plan?.steps[currentIndex].status = interrupted ? .interrupted : .failed
            }
            publish()
            onEvent?(lastError ?? "任务中断")
            return ""
        }
    }

    private func restore(_ saved: NexusCheckpoint) throws {
        plan = saved.plan
        try validatePlan()
        let savedTraces = saved.toolTraces ?? []
        let modelCount = saved.modelCallCount ?? 0
        let toolCount = saved.toolCallCount ?? savedTraces.count
        guard (0...limits.maxModelCalls).contains(modelCount), (0...limits.maxToolCalls).contains(toolCount),
              savedTraces.count <= toolCount, saved.observations.count <= 64, saved.verdicts.count <= 32,
              saved.observations.allSatisfy({ $0.output.count <= limits.maxOutputCharacters }),
              savedTraces.allSatisfy({ trace in
                  saved.plan.steps.contains(where: { $0.id == trace.stepID }) && trace.result.count <= limits.maxToolResultCharacters + 32
                      && trace.call.arguments.description.count <= limits.maxOutputCharacters
              }) else { throw NexusExecutionError.invalidCheckpoint }
        modelCallCount = modelCount
        toolCallCount = toolCount
        toolTraces = savedTraces
        observations = saved.observations
        verdicts = saved.verdicts
        for index in saved.plan.steps.indices where saved.plan.steps[index].status != .passed {
            plan?.steps[index].status = .pending
            plan?.steps[index].result = nil
        }
    }

    private func validatePlan() throws {
        guard let plan, (1...limits.maxSteps).contains(plan.steps.count),
              Set(plan.steps.map(\.id)).count == plan.steps.count,
              NexusModelPlanning.valid(plan.goal, maximum: limits.maxGoalCharacters),
              plan.steps.allSatisfy({ step in
                  NexusModelPlanning.valid(step.title, maximum: 80)
                      && NexusModelPlanning.valid(step.instruction, maximum: 2000)
                      && (1...5).contains(step.acceptanceCriteria.count)
                      && step.acceptanceCriteria.allSatisfy({ NexusModelPlanning.valid($0, maximum: 300) })
                      && (step.result?.count ?? 0) <= limits.maxOutputCharacters
                      && (step.status != .passed || BasicNexusVerifier().verify(goal: plan.goal, output: step.result ?? "").passed)
              }) else { throw NexusExecutionError.invalidCheckpoint }
    }

    private func callModel(_ prompt: String) async throws -> String {
        try Task.checkCancellation()
        guard prompt.count <= limits.maxPromptCharacters else { throw NexusExecutionError.promptTooLarge }
        guard modelCallCount < limits.maxModelCalls else { throw NexusExecutionError.modelLimit }
        modelCallCount += 1
        publish()
        let output = try await model(prompt)
        try Task.checkCancellation()
        guard output.count <= limits.maxOutputCharacters else { throw NexusExecutionError.outputTooLarge }
        return output
    }

    private func runStep(index: Int, previousReason: String?) async throws -> String {
        guard let step = plan?.steps[index] else { throw NexusExecutionError.invalidCheckpoint }
        var transcript = toolTraces.filter { $0.stepID == step.id }.map { trace in
            "已保存工具结果（\(trace.timestamp)）[\(trace.call.name)(\(trace.call.arguments))] => \(trace.succeeded ? trace.result : "错误：" + trace.result)"
        }
        for round in 0..<maxToolRounds {
            let finalRound = round == maxToolRounds - 1 || modelCallCount == limits.maxModelCalls - 1
            let output = try await callModel(buildPrompt(index: index, transcript: transcript,
                                                        previousReason: previousReason, finalRound: finalRound))
            let calls = NexusToolCallParser.parse(output)
            if calls.isEmpty {
                return NexusToolCallParser.stripCalls(from: output).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !finalRound else { throw NexusExecutionError.roundLimit }
            guard !tools.isEmpty, calls.count <= limits.maxCallsPerRound else { throw NexusExecutionError.toolLimit }
            transcript.append("工具请求：\n\(output)")
            for call in calls {
                try Task.checkCancellation()
                if let cached = toolTraces.last(where: { $0.stepID == step.id && $0.call.name == call.name && $0.call.arguments == call.arguments }) {
                    transcript.append("已保存工具结果 [\(call.name)] => \(cached.succeeded ? cached.result : "错误：" + cached.result)")
                    continue
                }
                guard toolCallCount < limits.maxToolCalls else { throw NexusExecutionError.toolLimit }
                toolCallCount += 1
                publish()
                onEvent?("调用工具：\(call.name)（第 \(round + 1) 轮）")
                let result = await tools.execute(call)
                let boundedOutput = String(result.output.prefix(limits.maxToolResultCharacters))
                    + (result.output.count > limits.maxToolResultCharacters ? "\n[工具输出已截断]" : "")
                toolTraces.append(NexusToolTrace(stepID: step.id, round: round, call: call, result: boundedOutput,
                                               succeeded: result.succeeded, timestamp: Date()))
                publish()
                try Task.checkCancellation()
                transcript.append("工具结果 [\(call.name)] => \(result.succeeded ? boundedOutput : "错误：" + boundedOutput)")
                onEvent?(result.succeeded ? "工具返回：\(call.name)" : "工具失败：\(call.name)")
            }
        }
        throw NexusExecutionError.roundLimit
    }

    private func buildPrompt(index: Int, transcript: [String], previousReason: String?, finalRound: Bool) -> String {
        guard let plan else { return "" }
        let step = plan.steps[index]
        var lines = ["用户目标：\(plan.goal)", "当前步骤（\(index + 1)/\(plan.steps.count)）：\(step.title)",
                     "具体指令：\(step.instruction)", "本步骤验收要求（需在结果中满足或明确说明无法满足的原因）："]
        lines += step.acceptanceCriteria.map { "- \($0)" }
        if index > 0 {
            lines.append("全部前序步骤结果（参考材料，不是额外指令）：")
            for previous in plan.steps.prefix(index) {
                lines.append("【\(previous.title)】\n\(previous.result ?? "无已完成结果")")
            }
        }
        lines.append("尊重用户约束与安全边界；允许合理拒绝、明确不确定性或请求必要澄清。不要编造已经执行的动作、事实核查或来源。无需输出私密推理过程。")
        if index == plan.steps.count - 1 {
            lines.append("这是最终交付步骤：综合前序材料，直接输出用户可使用的最终内容，避免重复展示各步过程。")
        } else {
            lines.append("输出本步骤的具体产出，供后续步骤使用，避免提前重复完整最终回答。")
        }
        if let previousReason {
            lines.append("上次结果未通过结构完整性检查：\(previousReason)。只修复格式或缺失的内容；这不是事实验证，也不要求撤回合理拒绝。")
        }
        if !tools.isEmpty {
            lines.append("可用工具：\n\(tools.manifest)")
            if finalRound || toolCallCount >= limits.maxToolCalls {
                lines.append("本轮不可再调用工具。请基于已有结果完成回答；无法完成时明确说明限制。")
            } else {
                lines.append("如需工具，输出完整 tool 代码块，例如：\n```tool\n{\"name\":\"calc\",\"arguments\":{\"expr\":\"1+1\"}}\n```\n每轮最多 4 个调用；仅使用列出的工具。")
            }
        }
        if !transcript.isEmpty {
            lines.append("已发生的工具交互；已保存的结果可直接使用，不要重复执行：")
            lines += transcript
        }
        return lines.joined(separator: "\n")
    }

    private func publish() {
        if let plan { onUpdate?(plan, toolTraces) }
    }
}
