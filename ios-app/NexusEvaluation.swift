import Foundation
import Combine

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
    @Published private(set) var lastError: String?
    private let url: URL
    private var observer: NSObjectProtocol?
    private var loadFailed = false

    init(directory: URL? = nil) {
        url = NexusStoreFile.directory(directory).appendingPathComponent("nexus-evaluations.json")
        do { records = Array((try NexusStoreFile.read([NexusEvaluationRecord].self, from: url) ?? []).suffix(1000)) }
        catch { loadFailed = true; lastError = "读取评估记录失败：\(error.localizedDescription)；请先清除损坏记录再保存。" }
        observer = NotificationCenter.default.addObserver(forName: .nexusDataWiped, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.records = []
                self.loadFailed = FileManager.default.fileExists(atPath: self.url.path)
                self.lastError = self.loadFailed ? "部分评估记录未能删除，请重试清除全部数据。" : nil
            }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    @discardableResult
    func clear() -> Bool {
        do { try NexusStoreFile.remove(url); records = []; lastError = nil; loadFailed = false; return true }
        catch { lastError = "清除评估记录失败：\(error.localizedDescription)"; return false }
    }

    @discardableResult
    func record(task: String, success: Bool, recovered: Bool, verified: Bool, latency: TimeInterval) -> Bool {
        guard !loadFailed else { return false }
        var next = records
        next.append(NexusEvaluationRecord(id: UUID(), task: String(task.prefix(4000)), success: success,
            recovered: recovered, verified: verified, latency: latency.isFinite ? max(0, latency) : 0, createdAt: Date()))
        next = Array(next.suffix(1000))
        do { try NexusStoreFile.write(next, to: url); records = next; lastError = nil; return true }
        catch { lastError = "保存评估记录失败：\(error.localizedDescription)"; return false }
    }

    var successRate: Double { rate { $0.success } }
    var recoveryRate: Double { rate { $0.recovered } }
    var verificationRate: Double { rate { $0.verified } }
    var averageLatency: TimeInterval { records.isEmpty ? 0 : records.map(\.latency).reduce(0, +) / Double(records.count) }

    private func rate(_ predicate: (NexusEvaluationRecord) -> Bool) -> Double {
        records.isEmpty ? 0 : Double(records.filter(predicate).count) / Double(records.count)
    }
}
