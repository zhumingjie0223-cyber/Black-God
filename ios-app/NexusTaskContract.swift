import Foundation

struct NexusTaskContract: Codable, Equatable {
    let goal: String
    let successCriteria: [String]
    let maxRounds: Int
    let requiresVerification: Bool

    init(goal: String, successCriteria: [String] = [], maxRounds: Int = 6, requiresVerification: Bool = true) {
        self.goal = goal
        self.successCriteria = successCriteria
        self.maxRounds = max(1, maxRounds)
        self.requiresVerification = requiresVerification
    }
}

struct NexusStopDecision: Equatable {
    let shouldStop: Bool
    let reason: String
}

struct NexusTerminationPolicy {
    func decide(contract: NexusTaskContract, output: String, round: Int, verified: Bool) -> NexusStopDecision {
        if verified { return NexusStopDecision(shouldStop: true, reason: "验收通过") }
        if round >= contract.maxRounds { return NexusStopDecision(shouldStop: true, reason: "达到最大执行轮次") }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return NexusStopDecision(shouldStop: false, reason: "结果为空，继续执行") }
        return NexusStopDecision(shouldStop: false, reason: "等待验证或继续规划")
    }
}
