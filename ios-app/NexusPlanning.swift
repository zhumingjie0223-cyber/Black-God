import Foundation

/// Hard ceilings are shared by fresh and resumed executions. Counts include
/// planning and structural repair calls; saved work never resets these counts.
struct NexusExecutionLimits {
    let maxModelCalls: Int
    let maxToolCalls: Int
    let maxGoalCharacters: Int
    let maxPromptCharacters: Int
    let maxOutputCharacters: Int
    let maxToolResultCharacters: Int
    let maxSteps = 5
    let maxCallsPerRound = 4

    init(maxModelCalls: Int = 16, maxToolCalls: Int = 16, maxGoalCharacters: Int = 12000,
         maxPromptCharacters: Int = 48000, maxOutputCharacters: Int = 12000, maxToolResultCharacters: Int = 4000) {
        self.maxModelCalls = min(24, max(1, maxModelCalls))
        self.maxToolCalls = min(24, max(0, maxToolCalls))
        self.maxGoalCharacters = min(12000, max(1, maxGoalCharacters))
        self.maxPromptCharacters = min(48000, max(1, maxPromptCharacters))
        self.maxOutputCharacters = min(12000, max(1, maxOutputCharacters))
        self.maxToolResultCharacters = min(4000, max(1, maxToolResultCharacters))
    }
}

enum NexusModelPlanning {
    static func prompt(goal: String, manifest: String) -> String {
        """
        为用户任务生成 1 至 5 个具体、按顺序执行的步骤。简单问答只用 1 步，避免固定的“理解/生成/验证”重复流程。
        只有以下本地工具可用；不要假装能浏览网页、发送消息、修改外部账户或独立验证事实：
        \(manifest)
        每一步必须有具体指令和 1 至 5 条可说明的验收要求。最后一步必须整合全部前序结果，直接交付用户需要的最终内容。
        不要求输出私密推理过程。合理拒绝、不确定性说明、请求必要澄清都允许，不得为了完成任务编造数据或来源。
        只输出严格 JSON 对象，不能加代码围栏或额外字段，格式：
        {"steps":[{"title":"简短标题","instruction":"具体指令","acceptanceCriteria":["验收要求"]}]}
        title 最多 80 字，instruction 最多 2000 字，每条验收要求最多 300 字。
        用户目标：
        \(goal)
        """
    }

    static func parse(_ output: String, goal: String) -> NexusTaskPlan? {
        guard output.count <= 12000, let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["steps"], let steps = object["steps"] as? [[String: Any]],
              (1...5).contains(steps.count) else { return nil }
        var result: [NexusTaskStep] = []
        for step in steps {
            guard Set(step.keys) == ["title", "instruction", "acceptanceCriteria"],
                  let title = step["title"] as? String, valid(title, maximum: 80),
                  let instruction = step["instruction"] as? String, valid(instruction, maximum: 2000),
                  let criteria = step["acceptanceCriteria"] as? [String], (1...5).contains(criteria.count),
                  criteria.allSatisfy({ valid($0, maximum: 300) }) else { return nil }
            result.append(NexusTaskStep(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                        instruction: instruction, acceptanceCriteria: criteria))
        }
        return NexusTaskPlan(id: UUID(), goal: goal, steps: result, createdAt: Date())
    }

    static func valid(_ text: String, maximum: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= maximum
    }
}
