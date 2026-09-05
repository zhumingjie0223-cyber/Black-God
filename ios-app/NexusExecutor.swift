// ios-app/NexusExecutor.swift
import Foundation

// MARK: - Tool 协议与记录

protocol NexusTool {
    var name: String { get }
    var usage: String { get }
    func run(arguments: String) async throws -> String
}

struct NexusToolCall: Equatable {
    let name: String
    let arguments: String
    let raw: String
}

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

// MARK: - 工具注册表

final class NexusToolRegistry {
    private var tools: [String: NexusTool] = [:]

    init(tools: [NexusTool] = []) {
        for tool in tools { register(tool) }
    }

    func register(_ tool: NexusTool) {
        tools[tool.name.lowercased()] = tool
    }

    func tool(named name: String) -> NexusTool? {
        tools[name.lowercased()]
    }

    var isEmpty: Bool { tools.isEmpty }

    var manifest: String {
        tools.values
            .sorted { $0.name < $1.name }
            .map { "- \($0.name)：\($0.usage)" }
            .joined(separator: "\n")
    }

    static func defaultRegistry() -> NexusToolRegistry {
        NexusToolRegistry(tools: [NexusClockTool(), NexusCalculatorTool()])
    }
}

// MARK: - 内置工具

struct NexusClockTool: NexusTool {
    let name = "clock"
    let usage = "获取当前日期时间。参数：可选，时区标识如 Asia/Shanghai"

    func run(arguments: String) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        let tzID = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tzID.isEmpty, let tz = TimeZone(identifier: tzID) {
            formatter.timeZone = tz
        }
        return formatter.string(from: Date())
    }
}

struct NexusCalculatorTool: NexusTool {
    let name = "calc"
    let usage = "计算数学表达式。参数：表达式，如 (3+4)*2"

    func run(arguments: String) async throws -> String {
        let expr = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty else { throw NexusToolError.invalidArguments("表达式为空") }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ")
        guard expr.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw NexusToolError.invalidArguments("仅支持数字与 + - * / ( )")
        }
        let nsExpr = NSExpression(format: expr)
        guard let value = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
            throw NexusToolError.invalidArguments("无法求值：\(expr)")
        }
        return value.stringValue
    }
}

// MARK: - 工具调用解析

enum NexusToolCallParser {
    /// 支持两种格式：
    /// 1. `TOOL: name | arguments`
    /// 2. `{"tool":"name","arguments":"..."}`（arguments 可为字符串或对象）
    static func parse(_ output: String) -> [NexusToolCall] {
        var calls: [NexusToolCall] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let call = parseLinePrefix(line) {
                calls.append(call)
            } else if let call = parseJSON(line) {
                calls.append(call)
            }
        }
        return calls
    }

    private static func parseLinePrefix(_ line: String) -> NexusToolCall? {
        let prefixes = ["TOOL:", "tool:", "工具:", "工具："]
        for prefix in prefixes where line.hasPrefix(prefix) {
            let body = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return nil }
            let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let args = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            guard !name.isEmpty else { return nil }
            return NexusToolCall(name: name, arguments: args, raw: line)
        }
        return nil
    }

    private static func parseJSON(_ line: String) -> NexusToolCall? {
        guard line.hasPrefix("{"), line.hasSuffix("}"),
              let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["tool"] as? String, !name.isEmpty else { return nil }
        var args = ""
        if let s = obj["arguments"] as? String {
            args = s
        } else if let s = obj["args"] as? String {
            args = s
        } else if let any = obj["arguments"] ?? obj["args"],
                  let d = try? JSONSerialization.data(withJSONObject: any),
                  let s = String(data: d, encoding: .utf8) {
            args = s
        }
        return NexusToolCall(name: name, arguments: args, raw: line)
    }
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
        tools: NexusToolRegistry = .defaultRegistry(),
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
        do {
            let result = try await tool.run(arguments: call.arguments)
            return (result, true)
        } catch {
            return (error.localizedDescription, false)
        }
    }

    private func stripToolLines(_ output: String) -> String {
        output
            .components(separatedBy: .newlines)
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return NexusToolCallParser.parse(t).isEmpty
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                lines.append("如需使用工具，请单独一行输出：TOOL: 工具名 | 参数 。工具结果会在下一轮提供给你，随后再给出最终回答。若无需工具，直接输出结果。")
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
