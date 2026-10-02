import Foundation
import Darwin

struct NexusStorageSnapshot: Sendable {
    let used: Int64
    let free: Int64
    let budget: Int64
    let files: Int
    var remaining: Int64 { max(0, min(budget - used, free - NexusStorage.reserve)) }
    var stopReason: String? {
        if free < NexusStorage.reserve { return "手机剩余空间不足，已停止以保留基本空间。" }
        if used >= budget { return "内置运行环境已达到空间预算，请调整容量或整理文件。" }
        return nil
    }
}

struct NexusStorage {
    static let gib: Int64 = 1024 * 1024 * 1024
    static let reserve: Int64 = 256 * 1024 * 1024
    static let choices: [Int64] = [1, 2, 4, 8]
    /// 整镜像绝对硬顶（GiB），不可被设置项突破。
    static let absoluteCeilingGiB: Int64 = 8
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BlackGodLinux", isDirectory: true)
    }
    static func budget(in defaults: UserDefaults = .standard) -> Int64 {
        let value = defaults.integer(forKey: "blackgod.linux.storageGiB")
        return (choices.contains(Int64(value)) ? Int64(value) : 2) * gib
    }
    /// 用户预算与绝对硬顶取较小值。
    static func hardBudget(in defaults: UserDefaults = .standard) -> Int64 {
        min(budget(in: defaults), absoluteCeilingGiB * gib)
    }
    /// 先按已有用量认领预算，再套绝对硬顶。
    static func hardBudget(adoptExistingUsage snapshot: NexusStorageSnapshot, defaults: UserDefaults = .standard) -> Int64 {
        min(adoptExistingUsage(snapshot, defaults: defaults), absoluteCeilingGiB * gib)
    }
    /// 超硬顶或手机空间不足时直接拒绝，不是软提醒。
    static func enforceHardCeiling(_ snapshot: NexusStorageSnapshot, adding bytes: Int64 = 0) throws {
        if let reason = snapshot.stopReason {
            throw NexusReasoningError.execution(reason)
        }
        if bytes > 0, snapshot.used + bytes > snapshot.budget {
            throw NexusReasoningError.execution(
                "整镜像硬顶 \(ByteCountFormatter.string(fromByteCount: snapshot.budget, countStyle: .binary))，当前已用 \(ByteCountFormatter.string(fromByteCount: snapshot.used, countStyle: .binary))，无法再写入 \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary))。"
            )
        }
        if snapshot.budget > absoluteCeilingGiB * gib {
            throw NexusReasoningError.execution("整镜像绝对硬顶为 \(absoluteCeilingGiB) GiB，当前预算配置无效。")
        }
    }
    // 首次升级按已有文件选择预算，不覆盖用户之后明确选择的容量。
    static func adoptExistingUsage(_ snapshot: NexusStorageSnapshot, defaults: UserDefaults = .standard) -> Int64 {
        if defaults.object(forKey: "blackgod.linux.storageGiB") == nil {
            let required = max(2 * gib, snapshot.used + reserve)
            let choice = choices.first { $0 * gib >= required } ?? choices.last!
            defaults.set(Int(choice), forKey: "blackgod.linux.storageGiB")
        }
        return budget(in: defaults)
    }
    private static let cacheLock = NSLock()
    private static var cached: [String: (Date, NexusStorageSnapshot)] = [:]
    private struct FileIdentity: Hashable {
        let device: dev_t
        let inode: ino_t
    }
    static func measureCached(root: URL, budget: Int64) throws -> NexusStorageSnapshot {
        try Task.checkCancellation()
        cacheLock.lock(); let prior = cached[root.path]; cacheLock.unlock()
        if let prior, Date().timeIntervalSince(prior.0) < 5 {
            return NexusStorageSnapshot(used: prior.1.used, free: prior.1.free, budget: budget, files: prior.1.files)
        }
        let snapshot = try measure(root: root, budget: budget)
        try Task.checkCancellation()
        cacheLock.lock()
        if cached.count > 16 { cached.removeAll() }
        cached[root.path] = (Date(), snapshot)
        cacheLock.unlock()
        return snapshot
    }
    static func measureInBackground(root: URL = root, budget: Int64 = budget(), useCache: Bool = false) async throws -> NexusStorageSnapshot {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try useCache ? measureCached(root: root, budget: budget) : measure(root: root, budget: budget)
        }
        return try await withTaskCancellationHandler {
            do {
                let snapshot = try await worker.value
                try Task.checkCancellation()
                return snapshot
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: { worker.cancel() }
    }
    static func measure(root: URL = root, budget: Int64 = budget()) throws -> NexusStorageSnapshot {
        try Task.checkCancellation()
        let fm = FileManager.default
        let volume = fm.fileExists(atPath: root.path) ? root : root.deletingLastPathComponent()
        let values = try fm.attributesOfFileSystem(forPath: volume.path)
        guard let free = (values[.systemFreeSize] as? NSNumber)?.int64Value else { throw NexusReasoningError.execution("无法读取手机剩余空间") }
        var used: Int64 = 0; var files = 0
        var seen = Set<FileIdentity>()
        if fm.fileExists(atPath: root.path) {
            // fts supplies lstat metadata in one traversal. Avoid NSURL resource-property
            // resolution for every hard-linked runtime file, without following symlinks.
            try root.withUnsafeFileSystemRepresentation { representation in
                guard let representation, let path = strdup(representation) else {
                    throw NexusReasoningError.execution("无法读取运行环境空间")
                }
                defer { Darwin.free(path) }
                var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
                guard let tree = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                defer { fts_close(tree) }
                while true {
                    try Task.checkCancellation()
                    errno = 0
                    guard let entry = fts_read(tree) else {
                        if errno != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                        break
                    }
                    let info = Int32(entry.pointee.fts_info)
                    if [FTS_ERR, FTS_DNR, FTS_NS].contains(info) {
                        if entry.pointee.fts_errno == ENOENT { continue }
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(entry.pointee.fts_errno))
                    }
                    guard info == FTS_F, let metadata = entry.pointee.fts_statp else { continue }
                    let id = FileIdentity(device: metadata.pointee.st_dev, inode: metadata.pointee.st_ino)
                    guard seen.insert(id).inserted else { continue }
                    used += Int64(metadata.pointee.st_size); files += 1
                }
            }
        }
        return NexusStorageSnapshot(used: used, free: free, budget: budget, files: files)
    }
    static func setBudget(_ gibibytes: Int64, snapshot: NexusStorageSnapshot, defaults: UserDefaults = .standard) throws {
        guard choices.contains(gibibytes), gibibytes * gib > snapshot.used else { throw NexusReasoningError.execution("容量必须高于当前文件用量") }
        guard snapshot.free >= reserve else { throw NexusReasoningError.execution("手机剩余空间不足，调整预算不能增加物理容量") }
        defaults.set(Int(gibibytes), forKey: "blackgod.linux.storageGiB")
    }
}
