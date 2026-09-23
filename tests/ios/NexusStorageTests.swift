import XCTest
@testable import BlackGod
final class NexusStorageTests: XCTestCase {
    func testBudgetCanExpandButCannotClaimPhysicalDiskGrowth() throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let snapshot = NexusStorageSnapshot(used: NexusStorage.gib, free: 10 * NexusStorage.gib, budget: 2 * NexusStorage.gib, files: 1)
        XCTAssertThrowsError(try NexusStorage.setBudget(1, snapshot: snapshot, defaults: defaults))
        try NexusStorage.setBudget(4, snapshot: snapshot, defaults: defaults)
        XCTAssertEqual(NexusStorage.budget(in: defaults), 4 * NexusStorage.gib)
        XCTAssertEqual(snapshot.free, 10 * NexusStorage.gib)
        XCTAssertThrowsError(try NexusStorage.setBudget(3, snapshot: snapshot, defaults: defaults))
    }
    func testLowDiskAndExceededBudgetBothStop() {
        XCTAssertNotNil(NexusStorageSnapshot(used: 5, free: 100, budget: 100, files: 1).stopReason)
        XCTAssertNotNil(NexusStorageSnapshot(used: 100, free: 10 * NexusStorage.gib, budget: 100, files: 1).stopReason)
        XCTAssertNil(NexusStorageSnapshot(used: 50, free: 10 * NexusStorage.gib, budget: 100, files: 1).stopReason)
        XCTAssertEqual(NexusStorageSnapshot(used: 100, free: 100, budget: 50, files: 1).remaining, 0)
    }
    func testMeasurementDoesNotFollowLinksOutsideRuntime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("runtime"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("runtime/file"))
        try Data(repeating: 2, count: 1000).write(to: root.appendingPathComponent("outside"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("runtime/link").path, withDestinationPath: root.appendingPathComponent("outside").path)
        let snapshot = try NexusStorage.measure(root: root.appendingPathComponent("runtime"))
        XCTAssertEqual(snapshot.used, 100); XCTAssertEqual(snapshot.files, 1)
    }
    func testExistingUsageMigrationDoesNotOverrideExplicitBudget() throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let snapshot = NexusStorageSnapshot(used: 4 * NexusStorage.gib, free: 20 * NexusStorage.gib, budget: 2 * NexusStorage.gib, files: 1)
        XCTAssertEqual(NexusStorage.adoptExistingUsage(snapshot, defaults: defaults), 8 * NexusStorage.gib)
        defaults.set(2, forKey: "blackgod.linux.storageGiB")
        XCTAssertEqual(NexusStorage.adoptExistingUsage(snapshot, defaults: defaults), 2 * NexusStorage.gib)
    }

    func testSharedSystemHardLinksAreNotDoubleCounted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("first"))
        try FileManager.default.linkItem(at: root.appendingPathComponent("first"), to: root.appendingPathComponent("second"))
        let snapshot = try NexusStorage.measure(root: root)
        XCTAssertEqual(snapshot.used, 100)
        XCTAssertEqual(snapshot.files, 1)
    }

    func testDirectorySymlinksDoNotEscapeRuntimeOrCountTargetFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("runtime")
        let outside = folder.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 31).write(to: root.appendingPathComponent("kept"))
        try Data(repeating: 2, count: 4096).write(to: outside.appendingPathComponent("hidden"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("directory-link"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("broken-link"), withDestinationURL: folder.appendingPathComponent("missing"))
        let snapshot = try NexusStorage.measure(root: root)
        XCTAssertEqual(snapshot.used, 31)
        XCTAssertEqual(snapshot.files, 1)
    }

    @MainActor
    func testCancelledBackgroundMeasurementDoesNotPopulateCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: root.appendingPathComponent("first"))
        let task = Task { try await NexusStorage.measureInBackground(root: root, useCache: true) }
        task.cancel()
        do { _ = try await task.value; XCTFail("已取消的测量不能交付或缓存结果") }
        catch is CancellationError {} catch { XCTFail(error.localizedDescription) }
        try Data(repeating: 2, count: 20).write(to: root.appendingPathComponent("second"))
        let complete = try NexusStorage.measureCached(root: root, budget: NexusStorage.gib)
        XCTAssertEqual(complete.used, 30)
        XCTAssertEqual(complete.files, 2)
    }

    @MainActor
    func testCancelledRequestCannotReturnAnExistingCachedMeasurement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try NexusStorage.measureCached(root: root, budget: NexusStorage.gib)
        let task = Task { try await NexusStorage.measureInBackground(root: root, useCache: true) }
        task.cancel()
        do { _ = try await task.value; XCTFail("命中缓存也必须遵守取消") }
        catch is CancellationError {} catch { XCTFail(error.localizedDescription) }
    }

}
