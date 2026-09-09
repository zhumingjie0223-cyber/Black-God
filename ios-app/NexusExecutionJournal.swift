import Foundation
import CryptoKit

struct NexusExecutionRecord: Codable, Identifiable {
    let id: UUID
    let workspace: UUID
    let commandDigest: String
    let startedAt: Date
    var endedAt: Date?
    var status: String
    var exitCode: Int?
}

/// Host-only evidence. No command text, model credentials or stdout is persisted.
@MainActor
final class NexusExecutionJournal {
    private let url: URL
    init(url: URL) { self.url = url }
    func records() throws -> [NexusExecutionRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([NexusExecutionRecord].self, from: Data(contentsOf: url))
    }
    private func write(_ records: [NexusExecutionRecord]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(records.suffix(200))).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    @discardableResult
    func recoverInterrupted() throws -> Int {
        var list = try records()
        var count = 0
        for index in list.indices where list[index].status == "running" {
            list[index].status = "interrupted"
            list[index].endedAt = Date()
            count += 1
        }
        if count > 0 { try write(list) }
        return count
    }
    func begin(workspace: UUID, command: String) throws -> UUID {
        var list = try records()
        let id = UUID()
        let digest = SHA256.hash(data: Data(command.utf8)).map { String(format: "%02x", $0) }.joined()
        list.append(NexusExecutionRecord(id: id, workspace: workspace, commandDigest: digest,
            startedAt: Date(), status: "running"))
        try write(list)
        return id
    }
    func finish(_ id: UUID, status: String, exitCode: Int? = nil) throws {
        var list = try records()
        guard let index = list.firstIndex(where: { $0.id == id }) else { throw NexusError.invalidResponse }
        list[index].status = status
        list[index].exitCode = exitCode
        list[index].endedAt = Date()
        try write(list)
    }
}
