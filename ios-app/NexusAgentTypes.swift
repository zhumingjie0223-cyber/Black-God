import Foundation

struct NexusTaskPlan: Codable, Equatable {
    let id: UUID
    let goal: String
    var steps: [NexusTaskStep]
    let createdAt: Date
}

struct NexusTaskStep: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let instruction: String
    let acceptanceCriteria: [String]
    var status: NexusStepStatus
    var result: String?

    init(title: String, instruction: String? = nil, acceptanceCriteria: [String] = ["给出清楚的结果，并明确限制与不确定性。"], status: NexusStepStatus = .pending, result: String? = nil) {
        self.id = UUID()
        self.title = title
        self.instruction = instruction ?? title
        self.acceptanceCriteria = acceptanceCriteria
        self.status = status
        self.result = result
    }

    private enum CodingKeys: String, CodingKey { case id, title, instruction, acceptanceCriteria, status, result }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        instruction = try values.decodeIfPresent(String.self, forKey: .instruction) ?? title
        acceptanceCriteria = try values.decodeIfPresent([String].self, forKey: .acceptanceCriteria) ?? ["给出清楚的结果，并明确限制与不确定性。"]
        status = try values.decode(NexusStepStatus.self, forKey: .status)
        result = try values.decodeIfPresent(String.self, forKey: .result)
    }
}

/// `passed` means structurally complete, not independently fact-checked.
enum NexusStepStatus: String, Codable { case pending, running, passed, failed, skipped, interrupted }

struct NexusObservation: Codable, Equatable {
    let stepID: UUID
    let output: String
    let timestamp: Date
}

struct NexusVerdict: Codable, Equatable {
    let passed: Bool
    let reason: String
    let checkedAt: Date
}

struct NexusCheckpoint: Codable {
    let plan: NexusTaskPlan
    let observations: [NexusObservation]
    let verdicts: [NexusVerdict]
    let savedAt: Date
    let toolTraces: [NexusToolTrace]?
    let modelCallCount: Int?
    let toolCallCount: Int?
    let lastError: String?

    init(plan: NexusTaskPlan, observations: [NexusObservation], verdicts: [NexusVerdict], savedAt: Date,
         toolTraces: [NexusToolTrace]? = nil, modelCallCount: Int? = nil, toolCallCount: Int? = nil, lastError: String? = nil) {
        self.plan = plan
        self.observations = observations
        self.verdicts = verdicts
        self.savedAt = savedAt
        self.toolTraces = toolTraces
        self.modelCallCount = modelCallCount
        self.toolCallCount = toolCallCount
        self.lastError = lastError
    }
}

protocol NexusPlanning {
    func makePlan(for goal: String) -> NexusTaskPlan
}

protocol NexusVerifying {
    func verify(goal: String, output: String) -> NexusVerdict
}

struct BasicNexusPlanner: NexusPlanning {
    func makePlan(for goal: String) -> NexusTaskPlan {
        NexusTaskPlan(id: UUID(), goal: goal, steps: [
            NexusTaskStep(title: "完成任务", instruction: "直接完成用户目标，交付可使用的最终内容；信息不足时说明必要限制或提出具体问题。")
        ], createdAt: Date())
    }
}

struct BasicNexusVerifier: NexusVerifying {}
