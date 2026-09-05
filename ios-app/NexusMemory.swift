import Foundation

struct NexusMemoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let kind: String
    let source: String
    let confidence: Double
    let createdAt: Date
    let expiresAt: Date?
}

@MainActor
final class NexusMemoryStore: ObservableObject {
    @Published private(set) var items: [NexusMemoryItem] = []
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("nexus-memory.json")
        load()
    }

    func remember(_ text: String, kind: String = "episodic", source: String = "runtime", confidence: Double = 0.8, expiresAt: Date? = nil) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let item = NexusMemoryItem(id: UUID(), text: value, kind: kind, source: source, confidence: min(max(confidence, 0), 1), createdAt: Date(), expiresAt: expiresAt)
        items.append(item)
        persist()
    }

    func search(_ query: String, limit: Int = 8) -> [NexusMemoryItem] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        return items.filter { item in
            guard item.expiresAt.map({ $0 > Date() }) ?? true else { return false }
            return terms.isEmpty || terms.contains(where: { item.text.lowercased().contains($0) })
        }.sorted { $0.confidence > $1.confidence }.prefix(limit).map { $0 }
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id }; persist() }
    private func persist() { guard let data = try? JSONEncoder().encode(items) else { return }; try? data.write(to: url, options: .atomic) }
    private func load() { guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode([NexusMemoryItem].self, from: data) else { return }; items = value }
}
