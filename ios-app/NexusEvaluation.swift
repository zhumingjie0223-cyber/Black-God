import Foundation
import Combine

/// Operational telemetry only. These fields do not establish task correctness.
struct NexusEvaluationRecord: Codable, Identifiable {
    let id: UUID
    let task: String
    let success: Bool
    let recovered: Bool
    let verified: Bool
    let latency: TimeInterval
    let createdAt: Date
    var measurementVersion: Int? = nil
    var recoveryAttempt: Bool? = nil
}

@MainActor
final class NexusEvaluationStore: ObservableObject {
    @Published private(set) var records: [NexusEvaluationRecord] = []
    @Published private(set) var lastError: String?
    private let url: URL
    private var canWrite = true

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nexus-evaluations.json")
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                guard (try self.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4 * 1024 * 1024 else {
                    throw NSError(domain: "BlackGod.Metrics", code: 1, userInfo: [NSLocalizedDescriptionKey: "记录文件超过读取上限"])
                }
                records = try JSONDecoder().decode([NexusEvaluationRecord].self, from: Data(contentsOf: self.url))
            }
        } catch { canWrite = false; lastError = "读取运行记录失败：" + error.localizedDescription }
    }

    func record(task: String, success: Bool, recovered: Bool, verified: Bool, latency: TimeInterval, recoveryAttempt: Bool = false) {
        guard canWrite else { return }
        var record = NexusEvaluationRecord(id: UUID(), task: String(task.prefix(500)), success: success,
            recovered: recovered && recoveryAttempt, verified: verified, latency: max(0, latency.isFinite ? latency : 0), createdAt: Date())
        record.measurementVersion = 2
        record.recoveryAttempt = recoveryAttempt
        let next = Array((records + [record]).suffix(1000))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            records = next; lastError = nil
        } catch { lastError = "保存运行记录失败：" + error.localizedDescription }
    }

    var current: [NexusEvaluationRecord] { records.filter { $0.measurementVersion == 2 } }
    var legacyCount: Int { records.count - current.count }
    var responseRate: Double? { rate(current) { $0.success } }
    var reviewRate: Double? { rate(current) { $0.verified } }
    var recoveryRate: Double? { rate(current.filter { $0.recoveryAttempt == true }) { $0.recovered } }
    var recoveryAttempts: Int { current.filter { $0.recoveryAttempt == true }.count }
    var averageLatency: TimeInterval? {
        let values = current.map(\.latency).filter { $0.isFinite && $0 >= 0 }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    private func rate(_ values: [NexusEvaluationRecord], _ predicate: (NexusEvaluationRecord) -> Bool) -> Double? {
        values.isEmpty ? nil : Double(values.filter(predicate).count) / Double(values.count)
    }
}
