import Foundation

struct NexusVaultSessionPayload: Codable, Sendable {
    let session: NexusSessionRecord
    let messages: [ChatMessage]
    let hasCheckpoint: Bool
}

struct NexusVaultExport: Codable, Sendable {
    let format: String
    let exportedAt: Date
    let sessions: [NexusVaultSessionPayload]
    let memory: [NexusMemoryItem]
    let skillCount: Int
    let skillNames: [String]
}

enum NexusDataVaultError: LocalizedError, Equatable {
    case confirmMismatch
    case nothingToExport

    var errorDescription: String? {
        switch self {
        case .confirmMismatch: return "确认口令不正确。请输入「确认删除」四个字。"
        case .nothingToExport: return "当前没有可导出的本地数据。"
        }
    }
}

/// 全应用本地数据保险库：导出会话/记忆/技能清单；危险清空需显式口令。
struct NexusDataVault {
    static let wipePhrase = "确认删除"
    let root: URL
    private let sessions: NexusSessionLibrary
    private let memoryURL: URL
    private let skillsURL: URL

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = base
        self.sessions = NexusSessionLibrary(root: base)
        self.memoryURL = base.appendingPathComponent("nexus-memory.json")
        self.skillsURL = base.appendingPathComponent("nexus-skills.json")
    }

    func exportAll(memory: [NexusMemoryItem], skills: [NexusSkill]) throws -> Data {
        let index = try sessions.bootstrap()
        var payloads: [NexusVaultSessionPayload] = []
        for session in index.sessions {
            let messages = (try? sessions.conversationStore(for: session.id).load()) ?? []
            let hasCheckpoint = FileManager.default.fileExists(atPath: sessions.checkpointURL(for: session.id).path)
            payloads.append(.init(session: session, messages: messages, hasCheckpoint: hasCheckpoint))
        }
        let curated = memory.filter(\.isCurated)
        guard !payloads.isEmpty || !curated.isEmpty || !skills.isEmpty else {
            throw NexusDataVaultError.nothingToExport
        }
        let payload = NexusVaultExport(
            format: "blackgod.vault.v1",
            exportedAt: Date(),
            sessions: payloads.sorted { $0.session.updatedAt > $1.session.updatedAt },
            memory: curated,
            skillCount: skills.count,
            skillNames: skills.map(\.current.content.name)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// 只清空全部会话与快捷指令检查点；记忆与技能保留。口令必须完全匹配。
    func wipeConversations(confirm: String) throws {
        guard confirm.trimmingCharacters(in: .whitespacesAndNewlines) == Self.wipePhrase else {
            throw NexusDataVaultError.confirmMismatch
        }
        let index = try sessions.bootstrap()
        for session in index.sessions {
            let folder = sessions.conversationURL(for: session.id).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
        }
        let fresh = NexusSessionRecord(title: "新对话")
        try FileManager.default.createDirectory(
            at: sessions.conversationURL(for: fresh.id).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sessions.conversationStore(for: fresh.id).save([])
        try sessions.saveIndex(NexusSessionIndex(activeID: fresh.id, sessions: [fresh]))
        let shortcut = root.appendingPathComponent("nexus-shortcuts.agent.json")
        if FileManager.default.fileExists(atPath: shortcut.path) {
            try FileManager.default.removeItem(at: shortcut)
        }
        let legacyChat = root.appendingPathComponent("nexus-conversation.json")
        let legacyAgent = root.appendingPathComponent("nexus-conversation.agent.json")
        let shortcutEpisodes = root.appendingPathComponent("nexus-shortcuts.agent.episodes.json")
        let legacyEpisodes = root.appendingPathComponent("nexus-conversation.episodes.json")
        for url in [legacyChat, legacyAgent, shortcutEpisodes, legacyEpisodes] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
