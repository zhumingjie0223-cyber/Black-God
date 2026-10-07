import XCTest
@testable import BlackGod

@MainActor
final class NexusWorkspaceTransactionTests: XCTestCase {
    private final class Files {
        var bytes: [String: Data] = [:]
        var writes = 0
        var removes = 0
        var readError: Error?
        var existenceError: Error?
        var writeError: Error?
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("blackgod-transactions-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func store(workspace: UUID = UUID(), root: URL, files: Files,
                       archiveWriter: ((Data, URL) throws -> Void)? = nil) -> NexusWorkspaceTransactions {
        NexusWorkspaceTransactions(workspace: workspace, backupRoot: root, reader: { path in
            if let error = files.readError { throw error }
            guard let data = files.bytes[path] else { throw NSError(domain: NSPOSIXErrorDomain, code: 2) }
            return data
        }, existence: { path in
            if let error = files.existenceError { throw error }
            return files.bytes[path] != nil
        }, writer: { path, data in
            if let error = files.writeError { throw error }
            files.writes += 1; files.bytes[path] = data
        }, remover: { path in
            files.removes += 1; files.bytes.removeValue(forKey: path)
        }, archiveWriter: archiveWriter)
    }

    private func call(_ name: String, _ arguments: [String: String]) -> NexusToolCall {
        NexusToolCall(id: UUID(), name: name, arguments: arguments)
    }

    private func backupID(_ result: NexusToolResult) throws -> String {
        let line = try XCTUnwrap(result.output.split(separator: "\n").first { $0.hasPrefix("backupID=") })
        return String(line.dropFirst("backupID=".count))
    }

    func testOldBytesAreDurablySavedBeforeWriteAndRestorableAfterReopening() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(), workspace = UUID()
        let original = Data([0xff, 0, 65, 0x80])
        files.bytes["报告.txt"] = original
        let transactions = store(workspace: workspace, root: root, files: files)
        let write = NexusTransactionalWorkspaceWriteTool(transactions: transactions, executor: { call in
            do {
                let archives = try FileManager.default.contentsOfDirectory(at: transactions.directory, includingPropertiesForKeys: nil)
                XCTAssertEqual(archives.count, 1)
                let url = try XCTUnwrap(archives.first)
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                let encoded = try XCTUnwrap(body["previousData"] as? String)
                XCTAssertEqual(Data(base64Encoded: encoded), original)
                let path = try XCTUnwrap(call.arguments["path"]), content = try XCTUnwrap(call.arguments["content"])
                files.bytes[path] = Data(content.utf8); files.writes += 1
                return NexusToolResult(callID: call.id, output: "已写入 报告.txt", succeeded: true)
            } catch {
                XCTFail(error.localizedDescription)
                return NexusToolResult(callID: call.id, output: error.localizedDescription, succeeded: false)
            }
        })
        let written = await write.execute(call("workspace_write", ["path": "报告.txt", "content": "新版"]))
        XCTAssertTrue(written.succeeded, written.output)
        XCTAssertTrue(written.output.contains("尚未执行恢复"))
        XCTAssertTrue(write.guaranteesRollback)
        let id = try backupID(written)
        let reopened = store(workspace: workspace, root: root, files: files)
        let restored = await NexusWorkspaceRestoreTool(transactions: reopened).execute(
            call("workspace_restore", ["backupID": id, "path": "报告.txt", "confirm": "恢复备份"]))
        XCTAssertTrue(restored.succeeded, restored.output)
        XCTAssertEqual(files.bytes["报告.txt"], original)
        XCTAssertEqual(files.removes, 0)
        let again = await NexusWorkspaceRestoreTool(transactions: reopened).execute(
            call("workspace_restore", ["backupID": id, "path": "报告.txt", "confirm": "恢复备份"]))
        XCTAssertFalse(again.succeeded)
        XCTAssertEqual(files.writes, 2)
    }

    func testNewFileRollbackDeletesOnlyTheWrittenFile() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(); files.bytes["other.txt"] = Data("用户资料".utf8)
        let transactions = store(root: root, files: files)
        let receipt = try await transactions.write(path: "新建.md", data: Data("新建内容".utf8))
        _ = try await transactions.restore(backupID: receipt.backupID.uuidString, path: receipt.path, confirm: "恢复备份")
        XCTAssertNil(files.bytes["新建.md"])
        XCTAssertEqual(files.bytes["other.txt"], Data("用户资料".utf8))
        XCTAssertEqual(files.removes, 1)
    }

    func testExistingEmptyFileRestoresEmptyBytesInsteadOfDeletingIt() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(); files.bytes["empty.txt"] = Data()
        let transactions = store(root: root, files: files)
        let receipt = try await transactions.write(path: "empty.txt", data: Data("new".utf8))
        _ = try await transactions.restore(backupID: receipt.backupID.uuidString, path: receipt.path, confirm: "恢复备份")
        XCTAssertNotNil(files.bytes["empty.txt"])
        XCTAssertEqual(files.bytes["empty.txt"], Data())
        XCTAssertEqual(files.removes, 0)
    }

    func testReaderAndExistenceErrorsNeverBecomeMissingAndNeverWrite() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(); files.bytes["existing.txt"] = Data("old".utf8)
        let transactions = store(root: root, files: files)
        let tool = NexusTransactionalWorkspaceWriteTool(transactions: transactions)
        files.readError = NSError(domain: NSPOSIXErrorDomain, code: 13)
        let unreadable = await tool.execute(call("workspace_write", ["path": "existing.txt", "content": "new"]))
        XCTAssertFalse(unreadable.succeeded)
        XCTAssertEqual(files.bytes["existing.txt"], Data("old".utf8))
        files.readError = nil; files.existenceError = NSError(domain: NSPOSIXErrorDomain, code: 5)
        let unstatable = await tool.execute(call("workspace_write", ["path": "new.txt", "content": "new"]))
        XCTAssertFalse(unstatable.succeeded)
        XCTAssertEqual(files.writes, 0)
        XCTAssertNil(files.bytes["new.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: transactions.directory.path))
    }

    func testBackupIOFailureAndArchiveQuotaStopBeforeTargetWrite() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("keep user file".utf8).write(to: blocked)
        let files = Files(); files.bytes["file.txt"] = Data("old".utf8)
        let broken = NexusTransactionalWorkspaceWriteTool(transactions: store(root: blocked, files: files))
        let failed = await broken.execute(call("workspace_write", ["path": "file.txt", "content": "new"]))
        XCTAssertFalse(failed.succeeded)
        XCTAssertEqual(try Data(contentsOf: blocked), Data("keep user file".utf8))
        files.bytes["file.txt"] = Data(repeating: 65, count: NexusWorkspaceTransactions.maxArchiveBytes)
        let oversized = await NexusTransactionalWorkspaceWriteTool(transactions: store(root: root, files: files)).execute(
            call("workspace_write", ["path": "file.txt", "content": "new"]))
        XCTAssertFalse(oversized.succeeded)
        XCTAssertEqual(files.writes, 0)
        XCTAssertEqual(files.bytes["file.txt"]?.count, NexusWorkspaceTransactions.maxArchiveBytes)
    }

    func testInvalidPathsAreRejectedWithoutReadingOrWritingTargets() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(), tool = NexusTransactionalWorkspaceWriteTool(transactions: store(root: root, files: files))
        files.bytes[String(repeating: "x", count: 120)] = Data("用户原文件".utf8)
        for path in ["../a", "/workspace/a", "a/../b", "a//b", "./a", "a/", "a\\b", "a\0b", "\na", " a",
                     String(repeating: "x", count: 121)] {
            let result = await tool.execute(call("workspace_write", ["path": path, "content": "new"]))
            XCTAssertFalse(result.succeeded, path)
        }
        XCTAssertEqual(files.writes, 0)
        XCTAssertEqual(files.bytes[String(repeating: "x", count: 120)], Data("用户原文件".utf8))
    }

    func testTaskScopedImportPermitAllowsOnlyTransactionPathAndRejectsOtherTasks() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(), workspace = UUID()
        let transactions = NexusWorkspaceTransactions(workspace: workspace, backupRoot: root,
            reader: { path in try XCTUnwrap(files.bytes[path]) }, existence: { files.bytes[$0] != nil },
            writer: { path, data in
                XCTAssertTrue(NexusWorkspaceTransactions.isActive(workspace: workspace))
                XCTAssertTrue(NexusWorkspaceTransactions.allowsImport(workspace: workspace, path: path))
                XCTAssertFalse(NexusWorkspaceTransactions.allowsImport(workspace: workspace, path: "other.txt"))
                let externalAllowed = await Task.detached {
                    await MainActor.run { NexusWorkspaceTransactions.allowsImport(workspace: workspace, path: path) }
                }.value
                XCTAssertFalse(externalAllowed)
                files.writes += 1; files.bytes[path] = data
            }, remover: { files.bytes.removeValue(forKey: $0) })
        _ = try await transactions.write(path: "file.txt", data: Data("new".utf8))
        XCTAssertFalse(NexusWorkspaceTransactions.isActive(workspace: workspace))
        XCTAssertTrue(NexusWorkspaceTransactions.allowsImport(workspace: workspace, path: "other.txt"))
        XCTAssertEqual(files.writes, 1)
    }

    func testRestoreRequiresExactConfirmationScopePathAndUnchangedWrittenBytes() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(); files.bytes["file.txt"] = Data("original".utf8)
        let transactions = store(root: root, files: files)
        let receipt = try await transactions.write(path: "file.txt", data: Data("written".utf8))
        let tool = NexusWorkspaceRestoreTool(transactions: transactions)
        for args in [
            ["backupID": receipt.backupID.uuidString, "path": receipt.path, "confirm": "确认删除"],
            ["backupID": receipt.backupID.uuidString, "path": "other.txt", "confirm": "恢复备份"],
            ["backupID": "../bad", "path": receipt.path, "confirm": "恢复备份"]
        ] {
            let result = await tool.execute(call("workspace_restore", args))
            XCTAssertFalse(result.succeeded)
        }
        let other = NexusWorkspaceRestoreTool(transactions: store(root: root, files: files))
        let wrongWorkspace = await other.execute(call("workspace_restore", ["backupID": receipt.backupID.uuidString,
            "path": receipt.path, "confirm": "恢复备份"]))
        XCTAssertFalse(wrongWorkspace.succeeded)
        files.bytes[receipt.path] = Data("用户后来编辑".utf8)
        let edited = await tool.execute(call("workspace_restore", ["backupID": receipt.backupID.uuidString,
            "path": receipt.path, "confirm": "恢复备份"]))
        XCTAssertFalse(edited.succeeded)
        XCTAssertEqual(files.bytes[receipt.path], Data("用户后来编辑".utf8))
        XCTAssertEqual(files.writes, 1)
        XCTAssertEqual(files.removes, 0)
    }

    func testRetentionIsTenBoundedPrivateArchivesAndUnknownFilesArePreserved() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(), transactions = store(root: root, files: files)
        for number in 0..<12 { _ = try await transactions.write(path: "file.txt", data: Data("version \(number)".utf8)) }
        let urls = try FileManager.default.contentsOfDirectory(at: transactions.directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(urls.count, NexusWorkspaceTransactions.maxBackups)
        for url in urls {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertLessThanOrEqual(try XCTUnwrap(attrs[.size] as? NSNumber).intValue, NexusWorkspaceTransactions.maxArchiveBytes)
            XCTAssertEqual(try XCTUnwrap(attrs[.posixPermissions] as? NSNumber).intValue, 0o600)
        }
        let unknown = transactions.directory.appendingPathComponent("用户保存.txt")
        try Data("keep".utf8).write(to: unknown)
        let blocked = await NexusTransactionalWorkspaceWriteTool(transactions: transactions).execute(
            call("workspace_write", ["path": "file.txt", "content": "next"]))
        XCTAssertFalse(blocked.succeeded)
        XCTAssertEqual(files.writes, 12)
        XCTAssertEqual(try Data(contentsOf: unknown), Data("keep".utf8))
    }

    func testRotationBackupFailurePreservesEveryExistingArchiveAndTarget() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(), workspace = UUID(), transactions = store(workspace: workspace, root: root, files: files)
        for number in 0..<10 { _ = try await transactions.write(path: "file.txt", data: Data("version \(number)".utf8)) }
        let urls = try FileManager.default.contentsOfDirectory(at: transactions.directory, includingPropertiesForKeys: nil)
        let before = try Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        let blocked = store(workspace: workspace, root: root, files: files, archiveWriter: { _, _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: 28)
        })
        let failed = await NexusTransactionalWorkspaceWriteTool(transactions: blocked).execute(
            call("workspace_write", ["path": "file.txt", "content": "new"]))
        XCTAssertFalse(failed.succeeded)
        let afterURLs = try FileManager.default.contentsOfDirectory(at: transactions.directory, includingPropertiesForKeys: nil)
        let after = try Dictionary(uniqueKeysWithValues: afterURLs.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        XCTAssertEqual(after, before)
        XCTAssertEqual(files.bytes["file.txt"], Data("version 9".utf8))
        XCTAssertEqual(files.writes, 10)
    }

    func testValidatedPendingArchiveFromInterruptedPublicationIsRecoveredWhileUnknownPendingIsPreserved() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(); files.bytes["file.txt"] = Data("old".utf8)
        let transactions = store(root: root, files: files)
        let receipt = try await transactions.write(path: "file.txt", data: Data("new".utf8))
        let published = transactions.directory.appendingPathComponent(receipt.backupID.uuidString + ".json")
        let pending = transactions.directory.appendingPathComponent(".pending-" + receipt.backupID.uuidString + ".json")
        try FileManager.default.moveItem(at: published, to: pending)
        files.bytes["file.txt"] = Data("old".utf8)
        _ = try await transactions.write(path: "file.txt", data: Data("next".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: transactions.directory, includingPropertiesForKeys: nil).count, 1)
        let unknown = transactions.directory.appendingPathComponent(".pending-" + UUID().uuidString + ".json")
        try Data("用户保存的未知资料".utf8).write(to: unknown)
        let blocked = await NexusTransactionalWorkspaceWriteTool(transactions: transactions).execute(
            call("workspace_write", ["path": "file.txt", "content": "another"]))
        XCTAssertFalse(blocked.succeeded)
        XCTAssertEqual(try Data(contentsOf: unknown), Data("用户保存的未知资料".utf8))
        XCTAssertEqual(files.bytes["file.txt"], Data("next".utf8))
    }

    func testFilesystemPrimitivesRejectSymlinksIncludingParentsAndDistinguishAbsence() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        try Data("private".utf8).write(to: real.appendingPathComponent("file"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: real)
        XCTAssertThrowsError(try NexusWorkspaceTransactionFiles.target(root: root, path: "link/file"))
        let link = root.appendingPathComponent("file-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real.appendingPathComponent("file"))
        XCTAssertThrowsError(try NexusWorkspaceTransactionFiles.target(root: root, path: "file-link"))
        XCTAssertThrowsError(try NexusWorkspaceTransactionFiles.read(link, limit: 100))
        let missing = try NexusWorkspaceTransactionFiles.target(root: root, path: "missing/new.txt")
        XCTAssertNil(try NexusWorkspaceTransactionFiles.attributes(missing))
        XCTAssertThrowsError(try NexusWorkspaceTransactionFiles.target(root: root, path: "real/file/child"))
    }

    func testBackupSymlinkIsRejectedAndWriterFailureNeverReportsRollbackVerified() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(); files.bytes["file"] = Data("old".utf8)
        let link = root.appendingPathComponent("backup-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let linked = await NexusTransactionalWorkspaceWriteTool(transactions: store(root: link, files: files)).execute(
            call("workspace_write", ["path": "file", "content": "new"]))
        XCTAssertFalse(linked.succeeded)
        files.writeError = NSError(domain: NSPOSIXErrorDomain, code: 28)
        let failed = await NexusTransactionalWorkspaceWriteTool(transactions: store(root: root, files: files)).execute(
            call("workspace_write", ["path": "file", "content": "new"]))
        XCTAssertFalse(failed.succeeded)
        XCTAssertTrue(failed.output.contains("backupID="))
        XCTAssertTrue(failed.output.contains("尚未执行或验证恢复"))
        XCTAssertEqual(files.bytes["file"], Data("old".utf8))
    }

    func testRestoreRejectsTamperedWorkspacePathAndArchiveSymlinkWithoutTargetMutation() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let files = Files(); files.bytes["file"] = Data("old".utf8)
        let transactions = store(root: root, files: files)
        let receipt = try await transactions.write(path: "file", data: Data("new".utf8))
        let url = transactions.directory.appendingPathComponent(receipt.backupID.uuidString + ".json")
        let originalArchive = try Data(contentsOf: url)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: originalArchive) as? [String: Any])
        let restore = NexusWorkspaceRestoreTool(transactions: transactions)
        let args = ["backupID": receipt.backupID.uuidString, "path": receipt.path, "confirm": "恢复备份"]
        for (key, value) in [("workspace", UUID().uuidString), ("path", "../outside")] {
            var altered = body; altered[key] = value
            try JSONSerialization.data(withJSONObject: altered).write(to: url, options: .atomic)
            let result = await restore.execute(call("workspace_restore", args))
            XCTAssertFalse(result.succeeded)
        }
        let outside = root.appendingPathComponent("archive-copy.json")
        try originalArchive.write(to: outside)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        let linked = await restore.execute(call("workspace_restore", args))
        XCTAssertFalse(linked.succeeded)
        XCTAssertEqual(files.bytes["file"], Data("new".utf8))
        XCTAssertEqual(files.writes, 1)
        XCTAssertEqual(files.removes, 0)
        XCTAssertEqual(try Data(contentsOf: outside), originalArchive)
    }
}
