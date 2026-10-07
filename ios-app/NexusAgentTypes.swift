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
    var status: NexusStepStatus
    var result: String?
    /// Stable source IDs and tool:<call UUID> pointers, preserved during a repair.
    var evidenceIDs: [String]
    /// True only when this step has observed successful execution evidence.
    var executionVerified: Bool?

    init(title: String, status: NexusStepStatus = .pending, result: String? = nil,
         evidenceIDs: [String] = [], executionVerified: Bool? = nil) {
        self.id = UUID()
        self.title = title
        self.status = status
        self.result = result
        self.evidenceIDs = evidenceIDs
        self.executionVerified = executionVerified
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, status, result, evidenceIDs, executionVerified
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        status = try values.decode(NexusStepStatus.self, forKey: .status)
        result = try values.decodeIfPresent(String.self, forKey: .result)
        evidenceIDs = try values.decodeIfPresent([String].self, forKey: .evidenceIDs) ?? []
        executionVerified = try values.decodeIfPresent(Bool.self, forKey: .executionVerified)
    }
}

enum NexusStepStatus: String, Codable { case pending, running, answered, passed, failed, skipped }

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
            NexusTaskStep(title: "理解目标"),
            NexusTaskStep(title: "生成响应"),
            NexusTaskStep(title: "验证结果")
        ], createdAt: Date())
    }
}

struct BasicNexusVerifier: NexusVerifying {}
