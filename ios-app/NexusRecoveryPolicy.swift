import Foundation

/// 恢复是重新核对当前状态，不继承可再次执行的写入或外部动作授权。
/// 这里的约束由程序判断，并随 checkpoint 保存；模型不能通过改计划解除。
struct NexusRecoveryPolicy: Codable, Equatable {
    let protectedOperation: NexusIntentOperation?
    let objectID: String?
    let objectTitle: String?
    let objectPath: String?
    let bindingEvidenceIDs: [String]

    static let readOnlyTools: Set<String> = [
        "read_file", "workspace_list", "workspace_read", "web_lookup",
        "clock", "calc", "memory_search", "skill_search", "skill_read",
        "plan", "verify", "dependency_plan", "causal_model", "shuyu", "echo"
    ]
    static let actionOperations: Set<NexusIntentOperation> = [.write, .delete, .restore, .send, .purchase, .execute]
    private static let fileActions: Set<NexusIntentOperation> = [.write, .delete, .restore]

    init(checkpoint: NexusAgentCheckpoint) {
        if let inherited = checkpoint.recoveryPolicy {
            self = inherited
            return
        }
        self.init(intentCard: checkpoint.intentCard ?? checkpoint.clarificationIntent)
    }

    private init(intentCard card: NexusIntentCard?) {
        protectedOperation = card.flatMap { Self.actionOperations.contains($0.operation) ? $0.operation : nil }
        objectID = card?.objectID
        objectTitle = card?.objectTitle
        objectPath = card?.objectPath
        bindingEvidenceIDs = Array((card?.evidenceIDs ?? []).prefix(24))
    }

    /// 旧版本可能没有任务卡；第一次恢复编译得到的动作绑定也必须保存。
    func preservingAction(from card: NexusIntentCard) -> Self {
        guard protectedOperation == nil, Self.actionOperations.contains(card.operation) else { return self }
        return Self(intentCard: card)
    }

    var protectsAction: Bool { protectedOperation != nil }

    /// 包括嵌套枢语调用；未知工具默认拒绝，不能只靠当前模型工具目录隐藏。
    func denialReason(for call: NexusToolCall) -> String? {
        Self.readOnlyTools.contains(call.name) ? nil :
            "中断恢复仅允许读取和核对；不会重放 \(call.name)。需要操作时请重新发送包含对象与约束的完整指令。"
    }

    /// 已绑定的文件操作可以自动降为读取该对象。旧卡不证明文件仍存在。
    /// 无可独立核对工具的发送、付款、命令等操作返回 nil，必须新指令。
    func inspectionCard(for card: NexusIntentCard, availableTools: Set<String>) -> NexusIntentCard? {
        guard let action = protectedOperation ?? (Self.actionOperations.contains(card.operation) ? card.operation : nil) else {
            return restricting(card, availableTools: availableTools)
        }
        guard Self.fileActions.contains(action),
              let path = objectPath ?? card.objectPath, !path.isEmpty,
              let readTool = ["workspace_read", "read_file"].first(where: availableTools.contains) else { return nil }
        let title = objectTitle ?? card.objectTitle ?? path
        let identity = objectID ?? card.objectID ?? "recovery-object:\(path)"
        return NexusIntentCard(goal: card.goal, operation: .inspect,
            objectID: identity, objectTitle: title, objectPath: path,
            recipient: nil, amount: nil, backupID: nil, authorizedCommand: nil,
            clarificationOptions: nil,
            constraints: card.constraints + ["恢复只读取当前状态，不重复原写入、删除或恢复；旧执行记录不能证明现状。"],
            successCriteria: ["以本次读取工具证据核对指定对象现状", "未读取或读取失败时如实说明，不能宣称原动作已完成"],
            missingSlots: [], risk: .low, clarification: nil, assumption: nil,
            resolvedGoal: "核对中断任务对象「\(title)」（\(path)）的当前状态。只读取，不执行原操作。",
            allowedTools: availableTools.intersection(Self.readOnlyTools), preferredTool: readTool,
            evidenceIDs: Array(Set(bindingEvidenceIDs + card.evidenceIDs)).sorted(),
            rollbackRequired: false, isAmbiguous: false)
    }

    func notice(for card: NexusIntentCard) -> String? {
        return "恢复仅核对「\(objectTitle ?? objectPath ?? card.objectTitle ?? "原对象")」的当前状态；原操作未重放。"
    }

    var needsNewInstruction: String {
        "中断任务的操作可能已经生效，现有工具不能独立确认。恢复已停在执行前；没有再次执行。请先明确要求核对现状，或重新发送包含对象与约束的完整操作指令。"
    }

    private func restricting(_ card: NexusIntentCard, availableTools: Set<String>) -> NexusIntentCard {
        NexusIntentCard(goal: card.goal, operation: card.operation, objectID: card.objectID,
            objectTitle: card.objectTitle, objectPath: card.objectPath, recipient: card.recipient,
            amount: card.amount, backupID: card.backupID, authorizedCommand: nil,
            clarificationOptions: card.clarificationOptions,
            constraints: card.constraints + ["中断恢复只允许读取和核对，不能重复有副作用的工具调用。"],
            successCriteria: card.successCriteria, missingSlots: card.missingSlots, risk: card.risk,
            clarification: card.clarification, assumption: card.assumption, resolvedGoal: card.resolvedGoal,
            allowedTools: card.allowedTools.intersection(availableTools).intersection(Self.readOnlyTools),
            preferredTool: card.preferredTool.flatMap { Self.readOnlyTools.contains($0) ? $0 : nil },
            evidenceIDs: card.evidenceIDs, rollbackRequired: false, isAmbiguous: card.isAmbiguous)
    }
}
