import Foundation

struct NexusEvaluationRecord: Codable, Identifiable {
    let id: UUID
    let task: String
    let success: Bool
    let recovered: Bool
    let verified: Bool
    let latency: TimeInterval
    let createdAt: Date
}

@MainActor
final class NexusEvaluationStore: ObservableObject {
    @Published private(set) var records: [NexusEvaluationRecord] = []
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("nexus-evaluations.json")
        load()
    }

    func record(task: String, success: Bool, recovered: Bool, verified: Bool, latency: TimeInterval) {
        records.append(NexusEvaluationRecord(id: UUID(), task: task, success: success, recovered: recovered, verified: verified, latency: latency, createdAt: Date()))
        if records.count > 1000 { records.removeFirst(records.count - 1000) }
        persist()
    }

    var successRate: Double { rate { $0.success } }
    var recoveryRate: Double { rate { $0.recovered } }
    var verificationRate: Double { rate { $0.verified } }
    var averageLatency: TimeInterval { records.isEmpty ? 0 : records.map(\.latency).reduce(0, +) / Double(records.count) }

    private func rate(_ predicate: (NexusEvaluationRecord) -> Bool) -> Double {
        records.isEmpty ? 0 : Double(records.filter(predicate).count) / Double(records.count)
    }
    private func persist() { guard let data = try? JSONEncoder().encode(records) else { return }; try? data.write(to: url, options: .atomic) }
    private func load() { guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode([NexusEvaluationRecord].self, from: data) else { return }; records = value }
}
