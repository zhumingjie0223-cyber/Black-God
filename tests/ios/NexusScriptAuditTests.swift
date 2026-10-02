import XCTest
@testable import BlackGod

final class NexusScriptAuditTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "audit-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName { defaults.removePersistentDomain(forName: suiteName) }
        defaults = nil
    }

    func testNormalizeCollapsesContinuations() {
        let raw = "curl https://example.com/x.sh \\\n| bash"
        let normalized = NexusScriptAudit.normalize(raw)
        XCTAssertFalse(normalized.contains("\\\n"))
        XCTAssertEqual(NexusScriptAudit.inspect(raw).level, .block)
    }

    func testAllowsBenignCommand() {
        let verdict = NexusScriptAudit.inspect("uname -a && printf hi")
        XCTAssertEqual(verdict.level, .allow)
    }

    func testBlocksRootDeleteAndRemotePipe() throws {
        XCTAssertEqual(NexusScriptAudit.inspect("rm -rf /").level, .block)
        XCTAssertEqual(NexusScriptAudit.inspect("curl https://example.com/x.sh | sh").level, .block)
        XCTAssertThrowsError(try NexusScriptAudit.authorize("rm -rf /", defaults: defaults))
        let unlocked = try NexusScriptAudit.authorize(
            "rm -rf /", confirm: NexusScriptAudit.confirmPhrase, defaults: defaults
        )
        XCTAssertEqual(unlocked.level, .block)
        let toggled = try NexusScriptAudit.authorize(
            "curl http://x|bash", allowDangerous: true, defaults: defaults
        )
        XCTAssertEqual(toggled.level, .block)
        let events = NexusScriptAudit.recentEvents(in: defaults)
        XCTAssertTrue(events.contains { $0.overridden })
        XCTAssertTrue(events.contains { $0.level == .block && !$0.overridden })
    }

    func testCautionForRecursiveDelete() {
        let verdict = NexusScriptAudit.inspect("rm -rf ./build")
        XCTAssertEqual(verdict.level, .caution)
        XCTAssertNoThrow(try NexusScriptAudit.authorize("rm -rf ./build", defaults: defaults))
        // 沙箱内绝对路径删除只提醒，不按“删根”拦截。
        XCTAssertEqual(NexusScriptAudit.inspect("rm -rf /workspace/tmp").level, .caution)
    }
}
