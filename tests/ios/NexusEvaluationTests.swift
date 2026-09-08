import XCTest
@testable import BlackGod

@MainActor
final class NexusEvaluationTests: XCTestCase {
    private var folder: URL!
    private var url: URL { folder.appendingPathComponent("metrics.json") }
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func testEmptyRatesRemainUnknown() {
        let store = NexusEvaluationStore(url: url)
        XCTAssertNil(store.responseRate); XCTAssertNil(store.reviewRate)
        XCTAssertNil(store.recoveryRate); XCTAssertNil(store.averageLatency)
    }
    func testRecoveryRateUsesOnlyExplicitRetries() {
        let store = NexusEvaluationStore(url: url)
        for _ in 0..<3 { store.record(task: "normal", success: true, recovered: true, verified: false, latency: 1) }
        XCTAssertNil(store.recoveryRate)
        store.record(task: "retry", success: true, recovered: true, verified: true, latency: 2, recoveryAttempt: true)
        store.record(task: "stopped", success: false, recovered: false, verified: false, latency: 3, recoveryAttempt: true)
        XCTAssertEqual(store.recoveryRate, 0.5)
        XCTAssertEqual(store.responseRate, 0.8)
        XCTAssertEqual(store.reviewRate, 0.2)
        XCTAssertEqual(store.recoveryAttempts, 2)
        XCTAssertEqual(NexusEvaluationStore(url: url).records.count, 5)
    }
    func testLegacyDataIsPreservedButExcluded() throws {
        let old = NexusEvaluationRecord(id: UUID(), task: "old", success: true, recovered: true, verified: true, latency: 2, createdAt: Date())
        try JSONEncoder().encode([old]).write(to: url)
        let store = NexusEvaluationStore(url: url)
        XCTAssertEqual(store.legacyCount, 1); XCTAssertNil(store.responseRate)
        store.record(task: "new", success: false, recovered: false, verified: false, latency: 3)
        XCTAssertEqual(store.records.first?.id, old.id)
        XCTAssertEqual(store.responseRate, 0)
        XCTAssertEqual(store.averageLatency, 3)
    }
    func testCorruptionCannotBeOverwritten() throws {
        let data = Data("broken".utf8); try data.write(to: url)
        let store = NexusEvaluationStore(url: url)
        store.record(task: "new", success: true, recovered: false, verified: false, latency: 1)
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertTrue(store.records.isEmpty)
    }
    func testWriteFailureDoesNotClaimRecordedSuccess() throws {
        try Data().write(to: url)
        let store = NexusEvaluationStore(url: url.appendingPathComponent("child"))
        store.record(task: "new", success: true, recovered: false, verified: false, latency: 1)
        XCTAssertNotNil(store.lastError); XCTAssertTrue(store.records.isEmpty)
    }
    func testInvalidLatencyIsSanitizedAndTaskIsBounded() {
        let store = NexusEvaluationStore(url: url)
        store.record(task: String(repeating: "长", count: 700), success: false, recovered: false, verified: false, latency: .infinity)
        XCTAssertEqual(store.records.first?.task.count, 500)
        XCTAssertEqual(store.averageLatency, 0)
    }
    func testChatCancellationIsRecordedOnceAndResumeHasSeparateDenominator() async throws {
        let entered = expectation(description: "chat started")
        let vm = ChatViewModel(store: NexusConversationStore(url: folder.appendingPathComponent("chat.json")), configured: { _ in true }, completion: { _, _ in
            entered.fulfill()
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return "unused"
        })
        vm.send("测试取消")
        await fulfillment(of: [entered], timeout: 2)
        vm.cancel(); vm.cancel()
        XCTAssertEqual(vm.evaluations.records.count, 1)
        XCTAssertEqual(vm.evaluations.responseRate, 0)
        XCTAssertNil(vm.evaluations.recoveryRate)
        let resumed = ChatViewModel(store: NexusConversationStore(url: folder.appendingPathComponent("chat.json")), configured: { _ in true }, completion: { _, _ in
            #"{"answer":"已恢复答复"}"#
        })
        resumed.resume()
        for _ in 0..<100 where resumed.isTyping { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(resumed.isTyping)
        XCTAssertEqual(resumed.evaluations.records.count, 2)
        XCTAssertEqual(resumed.evaluations.responseRate, 0.5)
        XCTAssertEqual(resumed.evaluations.recoveryRate, 1)
        XCTAssertEqual(resumed.evaluations.recoveryAttempts, 1)
    }

}
