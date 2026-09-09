import XCTest
import SQLite3
@testable import BlackGod

final class NexusRuntimeImageTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL, String) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? fm.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.main.url(forResource: "AlpineRootfs", withExtension: nil))
        let parent = root.appendingPathComponent("runtime")
        let old = parent.appendingPathComponent("alpine-3.22.1-arm64")
        let id = UUID().uuidString
        let workspace = old.appendingPathComponent("data/sessions/\(id)/workspace")
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("用户任务文件".utf8).write(to: workspace.appendingPathComponent("result.txt"))
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(old.appendingPathComponent("meta.db").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE stats(inode INTEGER PRIMARY KEY, stat BLOB); CREATE TABLE paths(path BLOB PRIMARY KEY, inode INTEGER);", nil, nil, nil), SQLITE_OK)
        let paths = ["/sessions", "/sessions/\(id)", "/sessions/\(id)/workspace", "/sessions/\(id)/workspace/result.txt"]
        for (index, path) in paths.enumerated() {
            let mode = index == 3 ? "A4810000E8030000E803000000000000" : "C0410000E8030000E803000000000000"
            let hex = path.utf8.map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(sqlite3_exec(db, "INSERT INTO stats VALUES(\(index+1),X'\(mode)'); INSERT INTO paths VALUES(X'\(hex)',\(index+1));", nil, nil, nil), SQLITE_OK)
        }
        return (source, parent, old, id)
    }
    func testUpgradePreservesUserFilesAndOldRuntime() throws {
        let (source, parent, old, id) = try fixture()
        let destination = try NexusRuntimeImage.install(source: source, parent: parent)
        XCTAssertNotEqual(destination, old)
        let suffix = "data/sessions/\(id)/workspace/result.txt"
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(suffix)), Data("用户任务文件".utf8))
        XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent(suffix)), Data("用户任务文件".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("data/sessions/\(id)/.ready").path))
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(destination.appendingPathComponent("meta.db").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT count(*) FROM paths WHERE CAST(path AS TEXT) LIKE '/sessions/%/workspace%'", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 2)
        XCTAssertEqual(try NexusRuntimeImage.install(source: source, parent: parent), destination)
    }
    func testNativeSymlinkFailsWithoutPublishingPartialUpgrade() throws {
        let (source, parent, old, id) = try fixture()
        let link = old.appendingPathComponent("data/sessions/\(id)/workspace/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try NexusRuntimeImage.install(source: source, parent: parent))
        let names = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        XCTAssertEqual(names, ["alpine-3.22.1-arm64"])
    }
    func testBrokenMetadataDoesNotReplaceOldFiles() throws {
        let (source, parent, old, id) = try fixture()
        try Data("corrupt".utf8).write(to: old.appendingPathComponent("meta.db"))
        XCTAssertThrowsError(try NexusRuntimeImage.install(source: source, parent: parent))
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("data/sessions/\(id)/workspace/result.txt"), encoding: .utf8), "用户任务文件")
    }
    func testMissingMetadataDoesNotAbandonWorkspace() throws {
        let (source, parent, old, _) = try fixture()
        try FileManager.default.removeItem(at: old.appendingPathComponent("meta.db"))
        XCTAssertThrowsError(try NexusRuntimeImage.install(source: source, parent: parent))
    }
    func testUnindexedFilePreventsIncompleteMigration() throws {
        let (source, parent, old, id) = try fixture()
        try Data("preserve".utf8).write(to: old.appendingPathComponent("data/sessions/\(id)/workspace/unindexed.txt"))
        XCTAssertThrowsError(try NexusRuntimeImage.install(source: source, parent: parent))
    }
    func testBundledLicenseAndPinnedImageArePresent() throws {
        let license = try XCTUnwrap(Bundle.main.url(forResource: "OPEN_SOURCE_LICENSES", withExtension: "md"))
        let text = try String(contentsOf: license, encoding: .utf8)
        XCTAssertTrue(text.contains("GNU GENERAL PUBLIC LICENSE"))
        XCTAssertTrue(text.contains("App Store"))
        let source = try XCTUnwrap(Bundle.main.url(forResource: "AlpineRootfs", withExtension: nil))
        let info = try JSONDecoder().decode(NexusRuntimeImage.Info.self, from: Data(contentsOf: source.appendingPathComponent("image-info.json")))
        XCTAssertEqual(info.alpineVersion, "3.22.5")
    }
}

@MainActor
extension NexusLinuxTests {
    func testUpdatedSystemPackagesAreUsedByGuest() async throws {
        let result = try await NexusLinuxRuntime.shared.execute(command: "apk info -v", workspace: UUID())
        XCTAssertTrue(result.succeeded, result.errorOutput)
        for version in ["musl-1.2.5-r12", "libcrypto3-3.5.8-r0", "libssl3-3.5.8-r0", "zlib-1.3.2-r0", "busybox-1.37.0-r20"] { XCTAssertTrue(result.output.contains(version), result.output) }
    }
}

@MainActor
extension NexusLinuxTests {
    func testImportedWorkspaceAndInterruptedBootstrapSurvivePreparation() async throws {
        let runtime = NexusLinuxRuntime.shared
        try runtime.prepare()
        for interrupted in [false, true] {
            let id = UUID()
            let root = "/sessions/" + id.uuidString + (interrupted ? ".previous" : "")
            let script = "mkdir -p '\(root)/workspace'; printf preserved > '\(root)/workspace/result.txt'; chown -R 1000:1000 '\(root)/workspace'\n"
            ISHKernel.shared.nextRoot = nil
            let status: Int = await withCheckedContinuation { continuation in
                _ = ISHShellExecutor.executeExecutable("/bin/sh", arguments: [], environment: [:], stdinData: Data(script.utf8), lineCallback: nil) { result in
                    continuation.resume(returning: Int(result.exitCode))
                }
            }
            XCTAssertEqual(status, 0)
            let result = try await runtime.execute(command: "cat result.txt; printf writable > after.txt; cat after.txt", workspace: id)
            XCTAssertTrue(result.succeeded, result.errorOutput)
            XCTAssertEqual(result.output, "preservedwritable")
        }
    }
}
