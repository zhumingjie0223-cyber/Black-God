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
        try JSONEncoder().encode(Array(messages.suffix(100))).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    var clearIntentURL: URL { url.appendingPathExtension("clearing") }

    /// The marker is committed first so a crash cannot resurrect a reply from the checkpoint.
    func clear(checkpointURL: URL, preserving unreadableFiles: [URL] = []) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !unreadableFiles.isEmpty {
            let backup = url.deletingLastPathComponent().appendingPathComponent("ConversationRecovery", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: backup, withIntermediateDirectories: true)
            for file in unreadableFiles where fm.fileExists(atPath: file.path) {
                try fm.copyItem(at: file, to: backup.appendingPathComponent(file.lastPathComponent))
            }
        }
        try Data("clear-v1".utf8).write(to: clearIntentURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try finishPendingClear(checkpointURL: checkpointURL)
    }

    @discardableResult
    func finishPendingClear(checkpointURL: URL) throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: clearIntentURL.path) else { return false }
        try save([])
        if fm.fileExists(atPath: checkpointURL.path) { try fm.removeItem(at: checkpointURL) }
        try fm.removeItem(at: clearIntentURL)
        return true
    }
}
