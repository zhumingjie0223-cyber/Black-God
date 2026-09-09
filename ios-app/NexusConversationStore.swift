import Foundation

/// 对话仅保存在应用支持目录，写入失败会向界面返回错误。
struct NexusConversationStore {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nexus-conversation.json")
    }
    func load() throws -> [ChatMessage] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ChatMessage].self, from: Data(contentsOf: url))
    }
    func save(_ messages: [ChatMessage]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(messages.suffix(100))).write(to: url, options: .atomic)
    }
}
