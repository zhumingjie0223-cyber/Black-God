// ios-app/NexusExecutor.swift
import Foundation

// MARK: - 工具调用记录与错误

struct NexusToolTrace {
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
        var parser = Parser(Array(expression))
        guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
        return value
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        init(_ chars: [Character]) { self.chars = chars }

        var isAtEnd: Bool { mutating get { skipSpaces(); return index >= chars.count } }

        mutating func skipSpaces() { while index < chars.count, chars[index] == " " { index += 1 } }

        mutating func peek() -> Character? { skipSpaces(); return index < chars.count ? chars[index] : nil }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
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
            }
            return value
        }

        mutating func parseFactor() -> Double? {
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
            return Double(digits)
        }
    }
}

/// 本文件内使用的默认工具注册表构造函数（只读安全工具集）。
private func nexusExecutorDefaultToolRegistry() -> NexusToolRegistry {
    NexusToolRegistry([NexusClockTool(), NexusCalculatorTool(), EchoTool()])
}

// MARK: - 执行器

@MainActor
final class NexusExecutor {
    typealias ModelCall = (String) async throws -> String

    private(set) var plan: NexusTaskPlan?
    private(set) var observations: [NexusObservation] = []
    private(set) var verdicts: [NexusVerdict] = []
    private(set) var toolTraces: [NexusToolTrace] = []

    private let planner: NexusPlanning
    private let verifier: NexusVerifying
    private let model: ModelCall
    private let tools: NexusToolRegistry
    private let maxToolRounds: Int
    private let onEvent: ((String) -> Void)?

    init(
        planner: NexusPlanning = BasicNexusPlanner(),
        verifier: NexusVerifying = BasicNexusVerifier(),
        model: @escaping ModelCall = { try await NexusModelBridge.complete($0) },
        tools: NexusToolRegistry = nexusExecutorDefaultToolRegistry(),
        maxToolRounds: Int = 4,
        onEvent: ((String) -> Void)? = nil
    ) {
        self.planner = planner
        self.verifier = verifier
        self.model = model
        self.tools = tools
        self.maxToolRounds = max(1, maxToolRounds)
        self.onEvent = onEvent
    }

    func run(goal: String) async -> String {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else { return "" }

        var plan = planner.makePlan(for: trimmedGoal)
        observations.removeAll()
        verdicts.removeAll()
        toolTraces.removeAll()
        self.plan = plan
        onEvent?("计划已生成：\(plan.steps.count) 步")

        var collected: [String] = []
        var context = ""

        for index in plan.steps.indices {
            if Task.isCancelled {
                for rest in index..<plan.steps.count where plan.steps[rest].status == .pending {
                    plan.steps[rest].status = .skipped
                }
                self.plan = plan
                onEvent?("任务已取消")
                break
            }

            plan.steps[index].status = .running
            self.plan = plan
            let step = plan.steps[index]
            onEvent?("开始步骤：\(step.title)")

            var finalOutput = ""
            var finalVerdict = NexusVerdict(passed: false, reason: "未执行", checkedAt: Date())

            for attempt in 0..<2 {
                if Task.isCancelled { break }
                let output = await runStepWithTools(
                    goal: trimmedGoal,
                    step: step,
                    index: index,
                    total: plan.steps.count,
                    context: context,
                    retry: attempt > 0,
                    previousReason: attempt > 0 ? finalVerdict.reason : nil
                )
                let verdict = verifier.verify(goal: trimmedGoal, output: output)
                observations.append(NexusObservation(stepID: step.id, output: output, timestamp: Date()))
                verdicts.append(verdict)
                finalOutput = output
                finalVerdict = verdict
                if verdict.passed { break }
                if attempt == 0 { onEvent?("步骤验证失败，重试一次：\(verdict.reason)") }
            }

            plan.steps[index].result = finalOutput
            plan.steps[index].status = Task.isCancelled && finalOutput.isEmpty ? .skipped : (finalVerdict.passed ? .passed : .failed)
            self.plan = plan
            onEvent?(finalVerdict.passed ? "步骤通过：\(step.title)" : "步骤失败：\(step.title)（\(finalVerdict.reason)）")

            if !finalOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                collected.append("【\(step.title)】\n\(finalOutput)")
                context = finalOutput
            }
        }

        let final = collected.joined(separator: "\n\n")
        onEvent?("执行完成")
        return final
    }

    // MARK: - 多轮工具闭环

    /// 单个步骤内的多轮循环：模型输出 → 解析工具调用 → 执行工具 → 结果回灌 → 再次调用模型，
    /// 直到模型不再请求工具或达到轮次上限。
    private func runStepWithTools(
        goal: String,
        step: NexusTaskStep,
        index: Int,
        total: Int,
        context: String,
        retry: Bool,
        previousReason: String?
    ) async -> String {
        var transcript: [String] = []
        var lastOutput = ""

        for round in 0..<maxToolRounds {
            if Task.isCancelled { break }

            let prompt = buildPrompt(
                goal: goal,
                step: step,
                index: index,
                total: total,
                context: context,
                retry: retry,
                previousReason: previousReason,
                transcript: transcript,
                finalRound: round == maxToolRounds - 1
            )

            let output: String
            do {
                output = try await model(prompt)
            } catch {
                onEvent?("模型调用失败：\(error.localizedDescription)")
                return lastOutput
            }

            let calls = tools.isEmpty ? [] : NexusToolCallParser.parse(output)
            if calls.isEmpty || round == maxToolRounds - 1 {
                lastOutput = stripToolLines(output)
                if !calls.isEmpty {
                    onEvent?("已达工具调用轮次上限，采用当前回答")
                }
                break
            }

            lastOutput = stripToolLines(output)
            transcript.append("模型：\n\(output)")

            var resultBlocks: [String] = []
            for call in calls {
                if Task.isCancelled { break }
                onEvent?("调用工具：\(call.name)（第 \(round + 1) 轮）")
                let (result, ok) = await executeTool(call)
                toolTraces.append(NexusToolTrace(
                    stepID: step.id,
                    round: round,
                    call: call,
                    result: result,
                    succeeded: ok,
                    timestamp: Date()
                ))
                observations.append(NexusObservation(
                    stepID: step.id,
                    output: "[工具 \(call.name)] \(result)",
                    timestamp: Date()
                ))
                onEvent?(ok ? "工具返回：\(call.name)" : "工具失败：\(call.name)（\(result)）")
                resultBlocks.append("[\(call.name)(\(call.arguments))] => \(ok ? result : "错误：\(result)")")
            }
            transcript.append("工具结果：\n" + resultBlocks.joined(separator: "\n"))
        }

        return lastOutput
    }

    private func executeTool(_ call: NexusToolCall) async -> (String, Bool) {
        guard let tool = tools.tool(named: call.name) else {
            return (NexusToolError.unknownTool(call.name).localizedDescription, false)
        }
        let result = await tool.execute(call)
        return (result.output, result.succeeded)
    }

    private func stripToolLines(_ output: String) -> String {
        NexusToolCallParser.stripCalls(from: output).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt

    private func buildPrompt(
        goal: String,
        step: NexusTaskStep,
        index: Int,
        total: Int,
        context: String,
        retry: Bool,
        previousReason: String?,
        transcript: [String],
        finalRound: Bool
    ) -> String {
        var lines: [String] = []
        lines.append("目标：\(goal)")
        lines.append("当前步骤（\(index + 1)/\(total)）：\(step.title)")
        if !context.isEmpty {
            lines.append("上一步结果：\n\(context)")
        }
        if retry, let reason = previousReason {
            lines.append("上次回答未通过验证：\(reason)。请直接、具体地围绕目标作答，覆盖目标中的关键词，不要以“抱歉/无法/不知道”开头。")
        }
        if !tools.isEmpty {
            lines.append("可用工具：\n\(tools.manifest)")
            if finalRound {
                lines.append("本轮为最后一轮，不可再调用工具，请基于已有信息直接给出最终结果。")
            } else {
                lines.append("""
                如需调用工具，请输出一个代码块，格式为：
                ```tool
                {"name": "工具名", "arguments": {"键": "值"}}
                ```
                可输出多个 tool 代码块。工具结果会在下一轮回灌给你，随后再给出最终回答。若无需工具，直接输出该步骤结果。
                """)
            }
        }
        if !transcript.isEmpty {
            lines.append("本步骤交互记录：")
            lines.append(contentsOf: transcript)
            lines.append("请结合以上工具结果继续。")
        }
        lines.append("请只输出该步骤的结果内容。")
        return lines.joined(separator: "\n")
    }
}
