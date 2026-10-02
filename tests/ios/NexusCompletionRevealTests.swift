import XCTest
@testable import BlackGod

@MainActor
final class NexusCompletionRevealTests: XCTestCase {
    func testMapsLiveStatesToOutcomes() {
        XCTAssertEqual(NexusCompletionReveal.Outcome.from(.answered), .success)
        XCTAssertEqual(NexusCompletionReveal.Outcome.from(.warning), .warning)
        XCTAssertEqual(NexusCompletionReveal.Outcome.from(.failed), .failure)
        XCTAssertNil(NexusCompletionReveal.Outcome.from(.running))
        XCTAssertNil(NexusCompletionReveal.Outcome.from(.idle))
        XCTAssertNil(NexusCompletionReveal.Outcome.from(.cancelled))
    }

    func testOutcomeCopyIsChinese() {
        XCTAssertEqual(NexusCompletionReveal.Outcome.success.title, "已完成")
        XCTAssertEqual(NexusCompletionReveal.Outcome.failure.title, "失败")
    }

    func testAutomationHostDisablesCompletionReveal() {
        // 单元测试进程带 XCTestConfigurationFilePath，正式包不会
        XCTAssertFalse(ChatMotion.completionRevealEnabled)
    }
}
