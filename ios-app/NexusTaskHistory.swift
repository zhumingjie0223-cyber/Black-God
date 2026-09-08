import Foundation
import Combine

enum NexusTaskHistoryStatus: String, Codable, CaseIterable {
    case completed, failed, cancelled
}

/// 使用独立的可序列化结构保存工具结果，不把执行器对象写入磁盘。
struct NexusTaskHistoryTrace: Codable, Identifiable, Equatable {
    let id: UUID
    let stepID: UUID
    let round: Int
    let name: String
    let arguments: [String: String]
    let result: String
    let succeeded: Bool
    let timestamp: Date

    init(id: UUID = UUID(), stepID: UUID, round: Int, name: String, arguments: [String: String], result: String, succeeded: Bool, timestamp: Date) {
        self.id = id; self.stepID = stepID; self.round = round; self.name = name
        self.arguments = arguments; self.result = result; self.succeeded = succeeded; self.timestamp = timestamp
    }
}

struct NexusTaskHistoryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let goal: String
    let model: String
    let plan: NexusTaskPlan?
    let toolTraces: [NexusTaskHistoryTrace]
    let result: String
    let status: NexusTaskHistoryStatus
    let createdAt: Date
    let updatedAt: Date
}

@MainActor
final class NexusTaskHistoryStore: ObservableObject {
    @Published private(set) var records: [NexusTaskHistoryRecord] = []
    @Published private(set) var lastError: String?
    private let url: URL
    private var observer: NSObjectProtocol?
    private var loadFailed = false

    init(directory: URL? = nil) {
        url = NexusStoreFile.directory(directory).appendingPathComponent("nexus-task-history.json")
        do { records = Self.bounded(try NexusStoreFile.read([NexusTaskHistoryRecord].self, from: url) ?? []) }
        catch { loadFailed = true; lastError = "读取任务历史失败：\(error.localizedDescription)；请先清除损坏记录再保存。" }
        observer = NotificationCenter.default.addObserver(forName: .nexusDataWiped, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.records = []
                self.loadFailed = FileManager.default.fileExists(atPath: self.url.path)
                self.lastError = self.loadFailed ? "部分任务历史未能删除，请重试清除全部数据。" : nil
            }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    @discardableResult
    func record(id: UUID = UUID(), goal: String, model: String, plan: NexusTaskPlan? = nil,
                toolTraces: [NexusTaskHistoryTrace] = [], result: String, status: NexusTaskHistoryStatus,
                createdAt: Date = Date()) -> Bool {
        let originalDate = records.first(where: { $0.id == id })?.createdAt ?? createdAt
        return upsert(NexusTaskHistoryRecord(id: id, goal: goal, model: model, plan: plan, toolTraces: toolTraces,
            result: result, status: status, createdAt: originalDate, updatedAt: Date()))
    }

    @discardableResult
    func upsert(_ record: NexusTaskHistoryRecord) -> Bool {
        guard !record.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "任务目标不能为空。"; return false
        }
        return commit(Self.bounded(records.filter { $0.id != record.id } + [record]))
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool { commit(records.filter { $0.id != id }) }

    @discardableResult
    func clear() -> Bool {
        do { try NexusStoreFile.remove(url); records = []; lastError = nil; loadFailed = false; return true }
        catch { lastError = "清除任务历史失败：\(error.localizedDescription)"; return false }
    }

    private func commit(_ next: [NexusTaskHistoryRecord]) -> Bool {
        guard !loadFailed else { return false }
        do { try NexusStoreFile.write(next, to: url); records = next; lastError = nil; return true }
        catch { lastError = "保存任务历史失败：\(error.localizedDescription)"; return false }
    }

    private static func bounded(_ saved: [NexusTaskHistoryRecord]) -> [NexusTaskHistoryRecord] {
        var seen = Set<UUID>()
        return saved.sorted { $0.updatedAt > $1.updatedAt }.filter { seen.insert($0.id).inserted }.prefix(50).map { record in
            let traces = record.toolTraces.suffix(30).map { trace in
                let arguments = Dictionary(uniqueKeysWithValues: trace.arguments.keys.sorted().prefix(16).map {
                    ($0, String((trace.arguments[$0] ?? "").prefix(500)))
                })
                return NexusTaskHistoryTrace(id: trace.id, stepID: trace.stepID, round: trace.round, name: String(trace.name.prefix(200)),
                    arguments: arguments, result: String(trace.result.prefix(2000)), succeeded: trace.succeeded, timestamp: trace.timestamp)
            }
            var plan = record.plan
            if let originalPlan = plan {
                let boundedSteps = Array(originalPlan.steps.prefix(50)).map { step in
                    var value = step
                    if let result = value.result { value.result = String(result.prefix(2000)) }
                    return value
                }
                plan?.steps = boundedSteps
            }
            return NexusTaskHistoryRecord(id: record.id, goal: String(record.goal.prefix(4000)), model: String(record.model.prefix(200)),
                plan: plan, toolTraces: traces, result: String(record.result.prefix(12000)), status: record.status,
                createdAt: record.createdAt, updatedAt: record.updatedAt)
        }
    }
}
