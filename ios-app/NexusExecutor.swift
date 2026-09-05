// ios-app/NexusExecutor.swift
import Foundation

@MainActor
final class NexusExecutor {
    typealias ModelCall = (String) async throws -> String

    private(set) var plan: NexusTaskPlan?
    private(set) var observations: [NexusObservation] = []
    private(set) var verdicts: [NexusVerdict] = []

    private let planner: NexusPlanning
    private let verifier: NexusVerifying
    private let model: ModelCall
    private let onEvent: ((String) -> Void)?

    init(
        planner: NexusPlanning = BasicNexusPlanner(),
        verifier: NexusVerifying = BasicNexusVerifier(),
        model: @escaping ModelCall = { try await NexusModelBridge.complete($0) },
        onEvent: ((String) -> Void)? = nil
    ) {
        self.planner = planner
        self.verifier = verifier
        self.model = model
        self.onEvent = onEvent
    }

    func run(goal: String) async -> String {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else { return "" }

        var plan = planner.makePlan(for: trimmedGoal)
        observations.removeAll()
        verdicts.removeAll()
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
                let prompt = buildPrompt(goal: trimmedGoal, step: step, index: index, total: plan.steps.count, context: context, retry: attempt > 0, previousReason: attempt > 0 ? finalVerdict.reason : nil)
                let output: String
                do {
                    output = try await model(prompt)
                } catch {
                    output = ""
                    onEvent?("模型调用失败：\(error.localizedDescription)")
                }
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

    private func buildPrompt(goal: String, step: NexusTaskStep, index: Int, total: Int, context: String, retry: Bool, previousReason: String?) -> String {
        var lines: [String] = []
        lines.append("目标：\(goal)")
        lines.append("当前步骤（\(index + 1)/\(total)）：\(step.title)")
        if !context.isEmpty {
            lines.append("上一步结果：\n\(context)")
        }
        if retry, let reason = previousReason {
            lines.append("上次回答未通过验证：\(reason)。请直接、具体地围绕目标作答，覆盖目标中的关键词，不要以“抱歉/无法/不知道”开头。")
        }
        lines.append("请只输出该步骤的结果内容。")
        return lines.joined(separator: "\n")
    }
}
