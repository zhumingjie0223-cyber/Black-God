import Foundation

/// 一条独立对话会话的元数据。消息与任务恢复文件按会话分目录存放。
struct NexusSessionRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "新对话", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = Self.cleanTitle(title)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func cleanTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "新对话" }
        if trimmed.count <= 36 { return trimmed }
        return String(trimmed.prefix(35)) + "…"
    }

    static func title(from messages: [ChatMessage]) -> String {
        guard let first = messages.first(where: { $0.role == "user" })?.content else { return "新对话" }
        return cleanTitle(first)
    }
}

struct NexusSessionIndex: Codable, Equatable, Sendable {
    var activeID: UUID
    var sessions: [NexusSessionRecord]
}

struct NexusSessionExport: Codable, Sendable {
    let format: String
    let exportedAt: Date
    let session: NexusSessionRecord
    let messages: [ChatMessage]
    let hasCheckpoint: Bool
}

/// 多会话目录：索引 + 每会话独立消息/任务恢复文件；长期记忆与技能仍放在根目录共享。
struct NexusSessionLibrary {
    static let maxSessions = 40
    let root: URL
    private let indexURL: URL
    private let sessionsRoot: URL
    private let legacyConversationURL: URL
    private let legacyCheckpointURL: URL

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = base
        self.indexURL = base.appendingPathComponent("nexus-sessions.json")
        self.sessionsRoot = base.appendingPathComponent("sessions", isDirectory: true)
        self.legacyConversationURL = base.appendingPathComponent("nexus-conversation.json")
        self.legacyCheckpointURL = base.appendingPathComponent("nexus-conversation.agent.json")
    }

    func conversationURL(for id: UUID) -> URL {
        sessionsRoot.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("messages.json")
    }

    func checkpointURL(for id: UUID) -> URL {
        conversationURL(for: id).deletingPathExtension().appendingPathExtension("agent.json")
    }

    func conversationStore(for id: UUID) -> NexusConversationStore {
        NexusConversationStore(url: conversationURL(for: id))
    }

    func checkpointStore(for id: UUID) -> NexusAgentCheckpointStore {
        NexusAgentCheckpointStore(url: checkpointURL(for: id))
    }

    /// 首次使用时把旧单文件对话迁进会话目录，并保证至少有一个活动会话。
    @discardableResult
    func bootstrap() throws -> NexusSessionIndex {
        if FileManager.default.fileExists(atPath: indexURL.path) {
            return try loadIndex()
        }
        let fm = FileManager.default
        try fm.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        let session = NexusSessionRecord()
        let store = conversationStore(for: session.id)
        let checkpoint = checkpointStore(for: session.id)
        if fm.fileExists(atPath: legacyConversationURL.path) {
            try fm.createDirectory(at: conversationURL(for: session.id).deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: legacyConversationURL, to: conversationURL(for: session.id))
            if fm.fileExists(atPath: legacyCheckpointURL.path) {
                try fm.moveItem(at: legacyCheckpointURL, to: checkpointURL(for: session.id))
            }
            let messages = (try? store.load()) ?? []
            var migrated = session
            migrated.title = NexusSessionRecord.title(from: messages)
            migrated.updatedAt = Date()
            let index = NexusSessionIndex(activeID: migrated.id, sessions: [migrated])
            try saveIndex(index)
            return index
        }
        try store.save([])
        _ = checkpoint
        let index = NexusSessionIndex(activeID: session.id, sessions: [session])
        try saveIndex(index)
        return index
    }

    func loadIndex() throws -> NexusSessionIndex {
        let data = try Data(contentsOf: indexURL)
        let index = try JSONDecoder().decode(NexusSessionIndex.self, from: data)
        guard !index.sessions.isEmpty, index.sessions.contains(where: { $0.id == index.activeID }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return index
    }

    func saveIndex(_ index: NexusSessionIndex) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(index).write(to: indexURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func list() throws -> [NexusSessionRecord] {
        try bootstrap().sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func activeID() throws -> UUID { try bootstrap().activeID }

    @discardableResult
    func create(title: String = "新对话") throws -> NexusSessionRecord {
        var index = try bootstrap()
        if index.sessions.count >= Self.maxSessions {
            throw NexusSessionError.limitReached
        }
        let session = NexusSessionRecord(title: title)
        try FileManager.default.createDirectory(
            at: conversationURL(for: session.id).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try conversationStore(for: session.id).save([])
        index.sessions.insert(session, at: 0)
        index.activeID = session.id
        try saveIndex(index)
        return session
    }

    @discardableResult
    func select(_ id: UUID) throws -> NexusSessionRecord {
        var index = try bootstrap()
        guard let session = index.sessions.first(where: { $0.id == id }) else {
            throw NexusSessionError.missing
        }
        index.activeID = id
        try saveIndex(index)
        return session
    }

    @discardableResult
    func rename(_ id: UUID, title: String) throws -> NexusSessionRecord {
        var index = try bootstrap()
        guard let offset = index.sessions.firstIndex(where: { $0.id == id }) else {
            throw NexusSessionError.missing
        }
        index.sessions[offset].title = NexusSessionRecord.cleanTitle(title)
        index.sessions[offset].updatedAt = Date()
        try saveIndex(index)
        return index.sessions[offset]
    }

    /// 用当前消息刷新标题与更新时间；标题仍是「新对话」时才自动改写。
    @discardableResult
    func touch(_ id: UUID, messages: [ChatMessage], forceTitle: Bool = false) throws -> NexusSessionRecord {
        var index = try bootstrap()
        guard let offset = index.sessions.firstIndex(where: { $0.id == id }) else {
            throw NexusSessionError.missing
        }
        index.sessions[offset].updatedAt = Date()
        if forceTitle || index.sessions[offset].title == "新对话" {
            index.sessions[offset].title = NexusSessionRecord.title(from: messages)
        }
        try saveIndex(index)
        return index.sessions[offset]
    }

    /// 删除指定会话；若删的是当前会话，自动切到最近一条，若已空则新建。
    @discardableResult
    func delete(_ id: UUID) throws -> NexusSessionIndex {
        var index = try bootstrap()
        guard index.sessions.contains(where: { $0.id == id }) else {
            throw NexusSessionError.missing
        }
        if index.sessions.count == 1 {
            throw NexusSessionError.cannotDeleteLast
        }
        index.sessions.removeAll { $0.id == id }
        if index.activeID == id {
            index.activeID = index.sessions.sorted { $0.updatedAt > $1.updatedAt }.first!.id
        }
        try saveIndex(index)
        let folder = conversationURL(for: id).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        return index
    }

    func export(_ id: UUID) throws -> Data {
        let index = try bootstrap()
        guard let session = index.sessions.first(where: { $0.id == id }) else {
            throw NexusSessionError.missing
        }
        let messages = try conversationStore(for: id).load()
        let hasCheckpoint = FileManager.default.fileExists(atPath: checkpointURL(for: id).path)
        let payload = NexusSessionExport(
            format: "blackgod.session.v1",
            exportedAt: Date(),
            session: session,
            messages: messages,
            hasCheckpoint: hasCheckpoint
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    func exportPlainText(_ id: UUID) throws -> String {
        let index = try bootstrap()
        guard let session = index.sessions.first(where: { $0.id == id }) else {
            throw NexusSessionError.missing
        }
        let messages = try conversationStore(for: id).load()
        var lines: [String] = ["# \(session.title)", ""]
        for message in messages {
            let role = message.role == "user" ? "你" : "Black God"
            lines.append("## \(role)")
            lines.append(message.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    struct SearchHit: Identifiable, Equatable, Sendable {
        var id: String { sessionID.uuidString + "/" + messageID.uuidString }
        let sessionID: UUID
        let sessionTitle: String
        let messageID: UUID
        let role: String
        let snippet: String
        let updatedAt: Date
    }

    /// 跨会话词面检索；按会话更新时间与命中位置排序，最多返回 limit 条。
    func search(_ query: String, limit: Int = 40) throws -> [SearchHit] {
        let terms = query.lowercased().split { $0.isWhitespace || $0.isNewline }.map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        let index = try bootstrap()
        var hits: [SearchHit] = []
        for session in index.sessions.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let messages = (try? conversationStore(for: session.id).load()) ?? []
            // 每个会话只取一条最佳命中，避免同会话多条刷屏。
            if let message = messages.reversed().first(where: { message in
                let hay = message.content.lowercased()
                return terms.allSatisfy { hay.contains($0) }
            }) {
                hits.append(SearchHit(
                    sessionID: session.id,
                    sessionTitle: session.title,
                    messageID: message.id,
                    role: message.role,
                    snippet: Self.snippet(message.content, around: terms[0]),
                    updatedAt: session.updatedAt
                ))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    private static func snippet(_ text: String, around term: String, radius: Int = 48) -> String {
        let lower = text.lowercased()
        let needle = term.lowercased()
        if let range = lower.range(of: needle) {
            let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
            let slice = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = start == text.startIndex ? "" : "…"
            let suffix = end == text.endIndex ? "" : "…"
            return prefix + slice + suffix
        }
        let clipped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped.count <= 96 ? clipped : String(clipped.prefix(95)) + "…"
    }
}

enum NexusSessionError: LocalizedError, Equatable {
    case limitReached
    case missing
    case cannotDeleteLast

    var errorDescription: String? {
        switch self {
        case .limitReached: return "会话数量已达上限（\(NexusSessionLibrary.maxSessions)），请先删除不用的会话。"
        case .missing: return "找不到该会话。"
        case .cannotDeleteLast: return "至少保留一个会话；若只要清空内容，请用「清空当前对话」。"
        }
    }
}
