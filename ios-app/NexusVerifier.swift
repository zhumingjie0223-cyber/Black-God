import Foundation

struct NexusVerificationReport: Equatable {
    let passed: Bool
    let checks: [String: Bool]
    let reason: String
}

struct NexusIndependentVerifier {
    func verify(goal: String, output: String) -> NexusVerificationReport {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmpty = !cleanOutput.isEmpty
        let hasError = ["出错了", "失败", "error", "timeout"].contains { cleanOutput.localizedCaseInsensitiveContains($0) }
        let hasGoalSignal = cleanGoal.isEmpty || cleanOutput.localizedCaseInsensitiveContains(cleanGoal) || cleanOutput.count > 20
        let checks = ["non_empty": nonEmpty, "no_error_signal": !hasError, "goal_signal": hasGoalSignal]
        return NexusVerificationReport(passed: checks.values.allSatisfy { $0 }, checks: checks, reason: checks.values.allSatisfy { $0 } ? "独立验证通过" : "结果未满足全部验证条件")
    }
}
