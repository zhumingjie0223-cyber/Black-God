import Foundation

struct NexusRunMetrics: Codable, Equatable {
    var toolCalls = 0
    var successfulToolCalls = 0
    var failedToolCalls = 0
    var replans = 0
    var approvals = 0
    var rejections = 0
    var verifiedRuns = 0
    var failedRuns = 0

    var toolSuccessRate: Double { toolCalls == 0 ? 0 : Double(successfulToolCalls) / Double(toolCalls) }
    var verificationRate: Double { let total = verifiedRuns + failedRuns; return total == 0 ? 0 : Double(verifiedRuns) / Double(total) }
}
