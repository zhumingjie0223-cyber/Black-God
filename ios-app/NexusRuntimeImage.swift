import Foundation
import SQLite3

/// Installs a new immutable system image and imports only user workspaces.
/// The previous runtime stays untouched so a failed installation can be retried.
enum NexusRuntimeImage {
    struct Info: Codable { let id: String; let alpineVersion: String }
    static func install(source: URL, parent: URL) throws -> URL {
        let fm = FileManager.default
        let info = try JSONDecoder().decode(Info.self, from: Data(contentsOf: source.appendingPathComponent("image-info.json")))
        guard info.id.range(of: "^alpine-[a-z0-9.-]+-arm64$", options: .regularExpression) != nil else { throw failure("运行环境版本无效") }
        let destination = parent.appendingPathComponent(info.id, isDirectory: true)
        if fm.fileExists(atPath: destination.appendingPathComponent("meta.db").path) { return destination }
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent("install-" + UUID().uuidString)
        do {
            try fm.copyItem(at: source, to: staging)
            guard fm.fileExists(atPath: staging.appendingPathComponent("data/bin/busybox").path) else { throw failure("运行环境文件不完整") }
            let previous = parent.appendingPathComponent("alpine-3.22.1-arm64")
            if fm.fileExists(atPath: previous.path) {
                guard fm.fileExists(atPath: previous.appendingPathComponent("meta.db").path) else { throw failure("旧运行环境元数据缺失，已保留原文件") }
                try importWorkspaces(from: previous, into: staging)
            }
            try fm.moveItem(at: staging, to: destination)
            return destination
        } catch { try? fm.removeItem(at: staging); throw error }
    }

    static func importWorkspaces(from old: URL, into new: URL) throws {
        let fm = FileManager.default
        let sessions = old.appendingPathComponent("data/sessions")
        guard fm.fileExists(atPath: sessions.path) else { return }
        let sourceDB = try open(old.appendingPathComponent("meta.db"), flags: SQLITE_OPEN_READONLY)
        defer { sqlite3_close(sourceDB) }
        let targetDB = try open(new.appendingPathComponent("meta.db"), flags: SQLITE_OPEN_READWRITE)
        defer { sqlite3_close(targetDB) }
        var copied = Set<String>()
        var expectedPaths = Set<String>()
        for folder in try fm.contentsOfDirectory(at: sessions, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            guard UUID(uuidString: folder.lastPathComponent) != nil else { continue }
            let workspace = folder.appendingPathComponent("workspace")
            guard fm.fileExists(atPath: workspace.path) else { continue }
            try rejectHostLinks(folder)
            let target = new.appendingPathComponent("data/sessions/" + folder.lastPathComponent)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            try fm.copyItem(at: workspace, to: target.appendingPathComponent("workspace"))
            copied.insert(folder.lastPathComponent)
            let prefix = "/sessions/" + folder.lastPathComponent + "/workspace"
            expectedPaths.insert(prefix)
            if let entries = fm.enumerator(atPath: workspace.path) {
                for case let entry as String in entries { expectedPaths.insert(prefix + "/" + entry) }
            }
        }
        if copied.isEmpty { return }
        try execute(targetDB, "BEGIN IMMEDIATE")
        do {
            var query: OpaquePointer?
            guard sqlite3_prepare_v2(sourceDB, "SELECT path,inode,stat FROM paths JOIN stats USING(inode)", -1, &query, nil) == SQLITE_OK else { throw failure("无法读取旧工作区元数据") }
            defer { sqlite3_finalize(query) }
            var inodeMap: [Int64: Int64] = [:]
            var code = sqlite3_step(query)
            var imported = Set<String>()
            while code == SQLITE_ROW {
                let pathData = data(query, column: 0)
                guard let path = String(data: pathData, encoding: .utf8) else { throw failure("工作区路径编码无效") }
                let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                let parent = path == "/sessions"
                let selected = parts.count >= 2 && parts[0] == "sessions" && copied.contains(parts[1]) && (parts.count == 2 || parts[2] == "workspace")
                if parent || selected {
                    guard path == "/" + parts.joined(separator: "/"), !parts.contains("."), !parts.contains(".."), !path.utf8.contains(0) else { throw failure("工作区路径无效") }
                    let hostPath = old.appendingPathComponent("data" + path)
                    guard fm.fileExists(atPath: hostPath.path) else { throw failure("工作区文件缺失") }
                    let oldInode = sqlite3_column_int64(query, 1)
                    let stat = data(query, column: 2)
                    guard stat.count == 16 else { throw failure("工作区属性格式无效") }
                    let inode: Int64
                    if let existing = inodeMap[oldInode] { inode = existing }
                    else {
                        try insert(targetDB, sql: "INSERT INTO stats(stat) VALUES(?)", blobs: [stat])
                        inode = sqlite3_last_insert_rowid(targetDB); inodeMap[oldInode] = inode
                    }
                    var statement: OpaquePointer?
                    guard sqlite3_prepare_v2(targetDB, "INSERT INTO paths(path,inode) VALUES(?,?)", -1, &statement, nil) == SQLITE_OK else { throw failure("无法写入工作区索引") }
                    defer { sqlite3_finalize(statement) }
                    _ = pathData.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                    sqlite3_bind_int64(statement, 2, inode)
                    guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("无法写入工作区路径") }
                    imported.insert(path)
                }
                code = sqlite3_step(query)
            }
            guard code == SQLITE_DONE else { throw failure("读取旧工作区失败") }
            for id in copied {
                for path in ["/sessions", "/sessions/" + id, "/sessions/" + id + "/workspace"] {
                    guard imported.contains(path) else { throw failure("旧工作区索引不完整") }
                }
            }
            guard expectedPaths.isSubset(of: imported) else { throw failure("旧工作区文件索引不完整，已保留原文件") }
            // A new database inode forces iSH to rebuild native inode mappings.
            try execute(targetDB, "UPDATE meta SET db_inode=0; COMMIT")
        } catch { try? execute(targetDB, "ROLLBACK"); throw error }
    }
    private static func rejectHostLinks(_ url: URL) throws {
        let fm = FileManager.default
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw failure("工作区包含不支持的本机链接") }
        var readFailed = false
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], errorHandler: { _, _ in readFailed = true; return false }) else { throw failure("无法读取工作区") }
        for case let entry as URL in enumerator {
            if try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw failure("工作区包含不支持的本机链接") }
        }
        if readFailed { throw failure("读取工作区失败") }
    }
    private static func open(_ url: URL, flags: Int32) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let result = db else { if let db { sqlite3_close(db) }; throw failure("无法打开运行环境元数据") }
        return result
    }
    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure("运行环境元数据更新失败") }
    }
    private static func data(_ statement: OpaquePointer?, column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
    private static func insert(_ db: OpaquePointer, sql: String, blobs: [Data]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure("元数据写入失败") }
        defer { sqlite3_finalize(statement) }
        for (index, blob) in blobs.enumerated() { _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, Int32(index+1), $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) } }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("元数据写入失败") }
    }
    private static func failure(_ text: String) -> Error { NexusReasoningError.execution(text) }
}
