import Foundation
import Combine

struct NexusMemoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let kind: String
    let source: String
    let confidence: Double
    let createdAt: Date
    let expiresAt: Date?
}

/// 三类本地存储共用的原子写入与文件保护；读取失败不能伪装成成功。
enum NexusStoreFile {
    static func directory(_ supplied: URL?) -> URL {
        supplied ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 32 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

@MainActor
final class NexusMemoryStore: ObservableObject {
    @Published private(set) var items: [NexusMemoryItem] = []
    @Published private(set) var lastError: String?
    private let url: URL
    private var observer: NSObjectProtocol?
    private var loadFailed = false

    init(directory: URL? = nil) {
        url = NexusStoreFile.directory(directory).appendingPathComponent("nexus-memory.json")
        do {
            if let saved = try NexusStoreFile.read([NexusMemoryItem].self, from: url) {
                items = Self.bounded(saved)
            }
        } catch {
            loadFailed = true
            lastError = "读取记忆失败：\(error.localizedDescription)；请先清除损坏记录再保存。"
        }
        observer = NotificationCenter.default.addObserver(forName: .nexusDataWiped, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetAfterWipe() }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    /// 由用户主动收藏调用；重复文本更新原记录，保留编号与创建时间。
    @discardableResult
    func remember(_ text: String, kind: String = "episodic", source: String = "user", confidence: Double = 0.8, expiresAt: Date? = nil) -> Bool {
        let value = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !value.isEmpty else { lastError = "记忆内容不能为空。"; return false }
        guard expiresAt.map({ $0 > Date() }) ?? true else { lastError = "记忆的过期时间必须在未来。"; return false }
        let key = NexusStoreFile.normalized(value)
        let existing = items.first { NexusStoreFile.normalized($0.text) == key }
        let item = NexusMemoryItem(id: existing?.id ?? UUID(), text: value,
            kind: String(kind.prefix(80)), source: String(source.prefix(80)),
            confidence: confidence.isFinite ? min(max(confidence, 0), 1) : 0.8,
            createdAt: existing?.createdAt ?? Date(), expiresAt: expiresAt)
        return commit(Self.bounded(items.filter { $0.id != item.id } + [item]))
    }

    /// 中英文按词匹配，拒绝空查询和泛词；最多 8 条、合计 6000 字。
    func search(_ query: String, limit: Int = 8) -> [NexusMemoryItem] {
        guard limit > 0 else { return [] }
        let terms = Self.terms(String(query.prefix(500)))
        guard !terms.isEmpty else { return [] }
        let now = Date()
        let ranked = items.compactMap { item -> (NexusMemoryItem, Int)? in
            guard item.expiresAt.map({ $0 > now }) ?? true else { return nil }
            let text = NexusStoreFile.normalized(item.text)
            let words = Set(Self.terms(item.text, maximum: 2000))
            let score = terms.filter { term in
                term.unicodeScalars.contains(where: Self.isCJK) ? text.contains(term) : words.contains(term)
            }.count
            return score > 0 ? (item, score) : nil
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.confidence != $1.0.confidence { return $0.0.confidence > $1.0.confidence }
            return $0.0.createdAt > $1.0.createdAt
        }
        var result: [NexusMemoryItem] = []
        var remaining = 6000
        for (item, _) in ranked {
            guard result.count < min(limit, 8), remaining > 0 else { break }
            guard item.text.count <= remaining else { continue }
            result.append(item)
            remaining -= item.text.count
        }
        return result
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool { commit(items.filter { $0.id != id }) }

    @discardableResult
    func clear() -> Bool {
        do {
            try NexusStoreFile.remove(url)
            items = []; lastError = nil; loadFailed = false
            return true
        } catch { lastError = "清除记忆失败：\(error.localizedDescription)"; return false }
    }

    private func resetAfterWipe() {
        // 清空当前视图；若磁盘删除失败，保留错误并禁止后续写入覆盖残留数据。
        items = []
        if FileManager.default.fileExists(atPath: url.path) {
            loadFailed = true; lastError = "部分记忆文件未能删除，请重试清除全部数据。"
        } else { loadFailed = false; lastError = nil }
    }

    private func commit(_ next: [NexusMemoryItem]) -> Bool {
        guard !loadFailed else { return false }
        do {
            try NexusStoreFile.write(next, to: url)
            items = next; lastError = nil
            return true
        } catch { lastError = "保存记忆失败：\(error.localizedDescription)"; return false }
    }

    private static func bounded(_ saved: [NexusMemoryItem]) -> [NexusMemoryItem] {
        var keys = Set<String>()
        let now = Date()
        return saved.sorted { $0.createdAt > $1.createdAt }.compactMap { item in
            let text = String(item.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
            guard !text.isEmpty, item.expiresAt.map({ $0 > now }) ?? true,
                  keys.insert(NexusStoreFile.normalized(text)).inserted else { return nil }
            return NexusMemoryItem(id: item.id, text: text, kind: String(item.kind.prefix(80)), source: String(item.source.prefix(80)),
                confidence: item.confidence.isFinite ? min(max(item.confidence, 0), 1) : 0.8,
                createdAt: item.createdAt, expiresAt: item.expiresAt)
        }.prefix(200).map { $0 }
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "to", "of", "in", "on", "at", "for", "with", "is", "are", "was", "be", "it", "my", "me", "we", "you", "your", "this", "that", "what", "which", "how", "do", "does", "can", "could", "please", "want", "need", "tell", "about",
        "我们", "你们", "他们", "这个", "那个", "什么", "怎么", "如何", "为什么", "可以", "需要", "请问", "帮我", "一下", "告诉", "一个", "一些", "喜欢", "记得", "知道", "觉得", "使用", "回答"
    ]

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(scalar.value) || (0x20000...0x2FA1F).contains(scalar.value)
    }

    private static func terms(_ value: String, maximum: Int = 24) -> [String] {
        let text = NexusStoreFile.normalized(value)
        var terms = Set<String>()
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, _ in
            guard let word, word.count >= 2, !stopWords.contains(word) else { return }
            terms.insert(word)
        }
        return Array(terms.sorted().prefix(maximum))
    }
}
