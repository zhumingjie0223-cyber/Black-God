import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private enum NexusWorkspaceTransactionScope {
    struct ImportPermit: Sendable { let workspace: UUID; let path: String }
    @TaskLocal static var importPermit: ImportPermit?
}

/// Private, workspace-scoped backups. A saved backup is evidence of recoverable
/// bytes, not evidence that restoration has already happened.
@MainActor
final class NexusWorkspaceTransactions {
    nonisolated static let maxBackups = 10
    nonisolated static let maxArchiveBytes = 2 * 1024 * 1024
    private static var activeWorkspaces = Set<UUID>()
    static func isActive(workspace: UUID) -> Bool { activeWorkspaces.contains(workspace) }
    static func allowsImport(workspace: UUID, path: String) -> Bool {
        guard isActive(workspace: workspace) else { return true }
        let permit = NexusWorkspaceTransactionScope.importPermit
        return permit?.workspace == workspace && permit?.path == path
    }
    let workspace: UUID
    let directory: URL

    typealias Reader = (String) async throws -> Data
    typealias Existence = (String) async throws -> Bool
    typealias Writer = (String, Data) async throws -> Void
    typealias Remover = (String) async throws -> Void
    private let prepare: () async throws -> Void
    private let reader: Reader
    private let existence: Existence
    private let writer: Writer
    private let remover: Remover
    private let archiveWriter: ((Data, URL) throws -> Void)?

    struct Receipt {
        let backupID: UUID
        let path: String
        let output: String
    }

    private struct Archive: Codable {
        let version: Int
        let workspace: UUID
        let backupID: UUID
        let path: String
        let previousData: Data?
        let writtenDigest: String
        let writtenSize: Int
        let createdAt: Date
        var restoredAt: Date?
    }

    convenience init(workspace: UUID, backupRoot: URL? = nil) {
        self.init(workspace: workspace, backupRoot: backupRoot, reader: { path in
            try NexusLinuxRuntime.shared.transactionReadFile(path, workspace: workspace)
        }, existence: { path in
            try NexusLinuxRuntime.shared.transactionFileExists(path, workspace: workspace)
        }, writer: { path, data in
            try await NexusLinuxRuntime.shared.transactionReplaceFile(data, path: path, workspace: workspace)
        }, remover: { path in
            try NexusLinuxRuntime.shared.transactionRemoveFile(path, workspace: workspace)
        }, prepare: {
            try await NexusLinuxRuntime.shared.ensureWorkspaceReady(workspace: workspace)
        })
    }

    init(workspace: UUID, backupRoot: URL? = nil, reader: @escaping Reader,
         existence: @escaping Existence, writer: @escaping Writer, remover: @escaping Remover,
         prepare: @escaping () async throws -> Void = {},
         archiveWriter: ((Data, URL) throws -> Void)? = nil) {
        self.workspace = workspace
        // Canonicalize the platform's app-support prefix (e.g. /var on iOS).
        // An explicitly supplied backupRoot still has to pass symlink checks.
        let root = backupRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .resolvingSymlinksInPath().appendingPathComponent("BlackGodWorkspaceBackups", isDirectory: true)
        directory = root.appendingPathComponent(workspace.uuidString, isDirectory: true)
        self.reader = reader; self.existence = existence; self.writer = writer
        self.remover = remover; self.prepare = prepare
        self.archiveWriter = archiveWriter
    }

    func write(path: String, data: Data,
               operation: ((String, Data) async throws -> String)? = nil) async throws -> Receipt {
        let safe = try Self.validate(path)
        guard !data.isEmpty, data.count <= Int(NexusWorkspaceQuota.maxSingleWrite) else {
            throw failure("内容需在 1 字节到 2 MiB 之间。")
        }
        try begin()
        defer { Self.activeWorkspaces.remove(workspace) }
        try Task.checkCancellation()
        try await prepare()
        let previous = try await readState(safe)
        let archive = Archive(version: 1, workspace: workspace, backupID: UUID(), path: safe,
            previousData: previous, writtenDigest: Self.digest(data), writtenSize: data.count,
            createdAt: Date(), restoredAt: nil)
        try save(archive, rotate: true)
        do {
            try Task.checkCancellation()
            // A later edit must never be mistaken for the bytes we backed up.
            guard try await readState(safe) == previous else {
                throw failure("文件在备份后发生变化，已取消写入。")
            }
            let permit = NexusWorkspaceTransactionScope.ImportPermit(workspace: workspace, path: safe)
            let output = try await NexusWorkspaceTransactionScope.$importPermit.withValue(permit) {
                if let operation { return try await operation(safe, data) }
                try await writer(safe, data)
                return "已写入 \(safe)"
            }
            guard try await readState(safe) == data else {
                throw failure("写入后的字节未通过核对；已保留原始备份。")
            }
            return Receipt(backupID: archive.backupID, path: safe, output: output)
        } catch {
            throw failure(error.localizedDescription + "\nbackupID=\(archive.backupID.uuidString)\npath=\(safe)\n已保存原始状态备份；尚未执行或验证恢复。")
        }
    }

    func restore(backupID: String, path: String, confirm: String) async throws -> Receipt {
        guard confirm == "恢复备份" else { throw failure("恢复需要 confirm=恢复备份。") }
        let safe = try Self.validate(path)
        guard let id = UUID(uuidString: backupID), id.uuidString == backupID.uppercased() else {
            throw failure("backupID 必须是有效的备份 UUID。")
        }
        try begin()
        defer { Self.activeWorkspaces.remove(workspace) }
        try Task.checkCancellation()
        var archive = try load(id)
        guard archive.path == safe else { throw failure("备份与请求的 path 不一致。") }
        guard archive.restoredAt == nil else { throw failure("该备份已恢复，不能再次覆盖文件。") }
        try await prepare()
        // Restore only the version that this transaction wrote. Newer user edits
        // are unknown and must not be silently replaced or deleted.
        guard let current = try await readState(safe), current.count == archive.writtenSize,
              Self.digest(current) == archive.writtenDigest else {
            throw failure("当前文件已变化或不存在；为保留后续修改，未执行恢复。")
        }
        try Task.checkCancellation()
        let permit = NexusWorkspaceTransactionScope.ImportPermit(workspace: workspace, path: safe)
        try await NexusWorkspaceTransactionScope.$importPermit.withValue(permit) {
            if let previous = archive.previousData { try await writer(safe, previous) }
            else { try await remover(safe) }
        }
        guard try await readState(safe) == archive.previousData else {
            throw failure("恢复后的文件状态未通过核对；请保留备份检查。")
        }
        archive.restoredAt = Date()
        try save(archive, rotate: false)
        return Receipt(backupID: id, path: safe, output: archive.previousData == nil
            ? "已撤销此次新建文件，并核对文件不存在：\(safe)"
            : "已恢复旧文件，并核对原始字节：\(safe)")
    }

    private func begin() throws {
        guard Self.activeWorkspaces.insert(workspace).inserted else {
            throw failure("此工作区正在备份或恢复，请稍后重试。")
        }
    }

    private func readState(_ path: String) async throws -> Data? {
        // Only a reliable typed existence check can establish absence. Reader,
        // permission, preparation and I/O errors are never treated as missing.
        guard try await existence(path) else { return nil }
        let data = try await reader(path)
        guard data.count <= Self.maxArchiveBytes else { throw failure("旧文件超过备份上限 2 MiB，未写入。") }
        return data
    }

    nonisolated static func validate(_ path: String) throws -> String {
        guard !path.isEmpty, path.utf8.count <= 1024, !path.hasPrefix("/"),
              !path.contains("\0"), !path.contains("\\"),
              path == path.trimmingCharacters(in: .whitespacesAndNewlines),
              path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw failure("path 必须是工作区内的有效相对路径。")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw failure("path 不能含空段、. 或 ..。")
        }
        // The existing import primitive truncates a single filename to 120
        // characters. Refuse that input so it cannot overwrite a different,
        // unbacked target after the transaction validated the full name.
        guard parts.count != 1 || path.count <= 120 else {
            throw failure("单段文件名最多 120 字，避免导入路径被截断。")
        }
        return path
    }

    private func ensureDirectory() throws {
        let fm = FileManager.default
        let base = directory.deletingLastPathComponent()
        for target in [base, directory] {
            // Reject supplied roots with symlinked ancestors, and reject an
            // archive directory that was replaced with a link.
            guard target.standardizedFileURL.path == target.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw failure("备份目录不能包含符号链接。")
            }
            if let attributes = try NexusWorkspaceTransactionFiles.attributes(target) {
                guard attributes.type == .directory else { throw failure("备份目录不是普通目录。") }
            } else {
                try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
        }
        #if os(iOS)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        #endif
    }

    private func save(_ archive: Archive, rotate: Bool) throws {
        try ensureDirectory()
        let encoded = try JSONEncoder().encode(archive)
        // Leave room for the restoration timestamp so status persistence cannot
        // exceed the archive quota after the original bytes have been restored.
        let limit = archive.restoredAt == nil ? Self.maxArchiveBytes - 256 : Self.maxArchiveBytes
        guard encoded.count <= limit else {
            throw failure("原始数据连同备份元数据超过每份 2 MiB 上限，未写入。")
        }
        let target = directory.appendingPathComponent(archive.backupID.uuidString + ".json")
        var obsolete: [Archive] = []
        if rotate {
            guard try NexusWorkspaceTransactionFiles.attributes(target) == nil else {
                throw failure("备份 ID 已存在，未覆盖任何文件。")
            }
            let backups = try knownBackups()
            obsolete = Array(backups.prefix(max(0, backups.count - Self.maxBackups + 1)))
        } else {
            guard let attributes = try NexusWorkspaceTransactionFiles.attributes(target), attributes.type == .file else {
                throw failure("备份文件不存在或类型不安全。")
            }
        }
        let staged = rotate ? directory.appendingPathComponent(".pending-" + archive.backupID.uuidString + ".json") : target
        if rotate {
            guard try NexusWorkspaceTransactionFiles.attributes(staged) == nil else {
                throw failure("备份暂存文件已存在，未覆盖任何文件。")
            }
        }
        defer { if rotate { try? FileManager.default.removeItem(at: staged) } }
        try persist(encoded, at: staged)
        if rotate {
            // Publish and sync the replacement before deleting any old recovery
            // data. A failed backup write must leave existing backups intact.
            try FileManager.default.moveItem(at: staged, to: target)
            try NexusWorkspaceTransactionFiles.sync(directory)
            for old in obsolete {
                try FileManager.default.removeItem(at: directory.appendingPathComponent(old.backupID.uuidString + ".json"))
            }
            try NexusWorkspaceTransactionFiles.sync(directory)
        }
    }

    private func persist(_ data: Data, at url: URL) throws {
        if let archiveWriter { try archiveWriter(data, url) }
        else {
        #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: url, options: .atomic)
        #endif
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try NexusWorkspaceTransactionFiles.sync(url)
        try NexusWorkspaceTransactionFiles.sync(directory)
        guard try NexusWorkspaceTransactionFiles.read(url, limit: Self.maxArchiveBytes) == data else {
            throw failure("备份落盘后未通过字节核对，未写入目标。")
        }
    }

    private func knownBackups() throws -> [Archive] {
        var backups: [Archive] = [], pending: [URL] = []
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if url.lastPathComponent.hasPrefix(".pending-") {
                let token = String(url.deletingPathExtension().lastPathComponent.dropFirst(".pending-".count))
                guard url.pathExtension == "json", let id = UUID(uuidString: token),
                      url.lastPathComponent == ".pending-" + id.uuidString + ".json" else {
                    throw failure("备份目录含未知暂存文件，未清理。")
                }
                let archive = try decodeArchive(at: url, id: id)
                guard archive.restoredAt == nil else { throw failure("暂存档状态无效，未清理。") }
                pending.append(url)
                continue
            }
            guard url.pathExtension == "json", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  url.lastPathComponent == id.uuidString + ".json" else {
                throw failure("备份目录含未知文件；未覆盖或清理这些文件。")
            }
            backups.append(try load(id))
        }
        // A crash before publication can leave only our fully validated pending
        // archive. It never authorized a target write and can be removed safely.
        for url in pending { try FileManager.default.removeItem(at: url) }
        if !pending.isEmpty { try NexusWorkspaceTransactionFiles.sync(directory) }
        return backups.sorted { $0.createdAt < $1.createdAt }
    }

    private func load(_ id: UUID) throws -> Archive {
        try ensureDirectory()
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        return try decodeArchive(at: url, id: id)
    }

    private func decodeArchive(at url: URL, id: UUID) throws -> Archive {
        let archive = try JSONDecoder().decode(Archive.self,
            from: NexusWorkspaceTransactionFiles.read(url, limit: Self.maxArchiveBytes))
        guard archive.version == 1, archive.workspace == workspace, archive.backupID == id,
              (try Self.validate(archive.path)) == archive.path,
              archive.previousData.map({ $0.count <= Self.maxArchiveBytes }) ?? true,
              (1...Int(NexusWorkspaceQuota.maxSingleWrite)).contains(archive.writtenSize),
              archive.writtenDigest.count == 64,
              archive.writtenDigest.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw failure("备份元数据不属于当前工作区或无效。")
        }
        return archive
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private func failure(_ text: String) -> NexusReasoningError { .execution(text) }

/// No-follow host file primitives for the selected runtime workspace. These do
/// not execute shell commands, and preserve ENOENT versus other filesystem errors.
enum NexusWorkspaceTransactionFiles {
    enum FileType { case file, directory }
    struct Attributes { let type: FileType; let size: Int }

    static func attributes(_ url: URL) throws -> Attributes? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            let code = errno
            if code == ENOENT { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        let mode = info.st_mode & mode_t(S_IFMT)
        guard mode == mode_t(S_IFREG) || mode == mode_t(S_IFDIR) else {
            throw failure("拒绝符号链接及非普通文件：\(url.lastPathComponent)")
        }
        return Attributes(type: mode == mode_t(S_IFREG) ? .file : .directory, size: Int(info.st_size))
    }

    static func target(root: URL, path: String) throws -> URL {
        _ = try NexusWorkspaceTransactions.validate(path)
        guard let rootInfo = try attributes(root), rootInfo.type == .directory else {
            throw failure("工作区尚未就绪或不是安全目录。")
        }
        var target = root
        let parts = path.split(separator: "/")
        for (index, part) in parts.enumerated() {
            target.appendPathComponent(String(part))
            if let info = try attributes(target) {
                guard index == parts.count - 1 ? info.type == .file : info.type == .directory else {
                    throw failure("path 的父目录或目标类型不安全。")
                }
            }
        }
        return target
    }

    static func read(_ url: URL, limit: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size >= 0, info.st_size <= off_t(limit) else {
            throw failure("文件类型不安全或超过备份读取上限。")
        }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                #if canImport(Darwin)
                Darwin.read(fd, bytes.baseAddress, bytes.count)
                #else
                Glibc.read(fd, bytes.baseAddress, bytes.count)
                #endif
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            if count == 0 { break }
            guard data.count + count <= limit else { throw failure("文件读取超过备份上限。") }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    static func sync(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
}

extension NexusLinuxRuntime {
    fileprivate func transactionTarget(_ path: String, workspace: UUID) throws -> URL {
        guard !isExecuting, let image = installedImageRoot() else {
            throw failure("工作区不可用或有另一项 Linux 任务正在运行。")
        }
        var root = image
        for part in ["data", "sessions", workspace.uuidString, "workspace"] {
            guard let attributes = try NexusWorkspaceTransactionFiles.attributes(root), attributes.type == .directory else {
                throw failure("工作区祖先目录不存在或包含符号链接。")
            }
            root.appendPathComponent(part, isDirectory: true)
        }
        return try NexusWorkspaceTransactionFiles.target(root: root, path: path)
    }
    func transactionFileExists(_ path: String, workspace: UUID) throws -> Bool {
        let target = try transactionTarget(path, workspace: workspace)
        return try NexusWorkspaceTransactionFiles.attributes(target) != nil
    }
    func transactionReadFile(_ path: String, workspace: UUID) throws -> Data {
        try NexusWorkspaceTransactionFiles.read(transactionTarget(path, workspace: workspace),
            limit: NexusWorkspaceTransactions.maxArchiveBytes)
    }
    func transactionReplaceFile(_ data: Data, path: String, workspace: UUID) async throws {
        guard NexusWorkspaceTransactions.allowsImport(workspace: workspace, path: path) else {
            throw failure("工作区交易期间拒绝外部导入。")
        }
        _ = try transactionTarget(path, workspace: workspace)
        if !data.isEmpty { try await importToWorkspace(data: data, named: path, workspace: workspace); return }
        // importToWorkspace intentionally rejects empty uploads; an existing
        // empty file is still a valid previous state and must be recoverable.
        try await ensureWorkspaceReady(workspace: workspace)
        let target = try transactionTarget(path, workspace: workspace)
        guard let root = hostWorkspaceURL(for: workspace) else { throw failure("工作区不可用。") }
        try NexusWorkspaceQuota.enforce(adding: 0, creatingFile: false, at: root)
        try Data().write(to: target, options: .atomic)
    }
    func transactionRemoveFile(_ path: String, workspace: UUID) throws {
        guard NexusWorkspaceTransactions.allowsImport(workspace: workspace, path: path) else {
            throw failure("工作区交易期间拒绝外部文件删除。")
        }
        let target = try transactionTarget(path, workspace: workspace)
        guard let info = try NexusWorkspaceTransactionFiles.attributes(target), info.type == .file else {
            throw failure("撤销新建操作只允许删除原目标普通文件。")
        }
        try FileManager.default.removeItem(at: target)
    }
}

struct NexusTransactionalWorkspaceWriteTool: NexusTool {
    let name = "workspace_write"
    let usage = "写入当前工作区文件，先原子保存原始状态备份。参数 path、content。成功返回 backupID、path；最多保留最近10份，每份含元数据不超过2 MiB。"
    let guaranteesRollback = true
    private let transactions: NexusWorkspaceTransactions
    private let executor: ((NexusToolCall) async -> NexusToolResult)?
    var isEnabled: () -> Bool = { NexusLinuxTool.enabled }

    @MainActor init(workspace: UUID, backupRoot: URL? = nil) {
        transactions = NexusWorkspaceTransactions(workspace: workspace, backupRoot: backupRoot)
        let underlying = NexusWorkspaceWriteTool(workspace: workspace)
        executor = { await underlying.execute($0) }
    }
    init(transactions: NexusWorkspaceTransactions, executor: ((NexusToolCall) async -> NexusToolResult)? = nil,
         isEnabled: @escaping () -> Bool = { true }) {
        self.transactions = transactions; self.executor = executor; self.isEnabled = isEnabled
    }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard isEnabled() else { return failed(call, "沙箱执行已关闭。") }
        guard let path = call.arguments["path"], let content = call.arguments["content"] else {
            return failed(call, "缺少 path 或 content。")
        }
        do {
            let operation: ((String, Data) async throws -> String)? = executor.map { execute in
                { path, _ in
                    var args = call.arguments; args["path"] = path
                    let result = await execute(NexusToolCall(id: call.id, name: call.name, arguments: args))
                    guard result.succeeded else { throw failure(result.output) }
                    return result.output
                }
            }
            let receipt = try await transactions.write(path: path, data: Data(content.utf8), operation: operation)
            return NexusToolResult(callID: call.id, output: receipt.output + "\nbackupID=\(receipt.backupID.uuidString)\npath=\(receipt.path)\n已保存原始状态备份；尚未执行恢复。", succeeded: true)
        } catch { return failed(call, error.localizedDescription) }
    }
}

struct NexusWorkspaceRestoreTool: NexusTool {
    let name = "workspace_restore"
    let usage = "恢复本工作区某次 workspace_write 的原始状态。参数 backupID、path，confirm 必须为「恢复备份」。已有后续修改时拒绝覆盖；新建文件恢复为不存在。"
    private let transactions: NexusWorkspaceTransactions
    var isEnabled: () -> Bool = { NexusLinuxTool.enabled }
    @MainActor init(workspace: UUID, backupRoot: URL? = nil) {
        transactions = NexusWorkspaceTransactions(workspace: workspace, backupRoot: backupRoot)
    }
    init(transactions: NexusWorkspaceTransactions, isEnabled: @escaping () -> Bool = { true }) {
        self.transactions = transactions; self.isEnabled = isEnabled
    }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard isEnabled() else { return failed(call, "沙箱执行已关闭。") }
        do {
            let receipt = try await transactions.restore(backupID: call.arguments["backupID"] ?? "",
                path: call.arguments["path"] ?? "", confirm: call.arguments["confirm"] ?? "")
            return NexusToolResult(callID: call.id, output: receipt.output + "\nbackupID=\(receipt.backupID.uuidString)\npath=\(receipt.path)", succeeded: true)
        } catch { return failed(call, error.localizedDescription) }
    }
}

private func failed(_ call: NexusToolCall, _ output: String) -> NexusToolResult {
    NexusToolResult(callID: call.id, output: output, succeeded: false)
}
