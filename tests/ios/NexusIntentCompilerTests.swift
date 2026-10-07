import XCTest
@testable import BlackGod

final class NexusIntentCompilerTests: XCTestCase {
    func testVagueSentenceBindsRecalledObject() {
        let card = NexusIntentCompiler.compile(
            "把上次那份报告看看",
            memories: ["金边客户报告", "未关记忆"],
            files: ["报告-金边.md"]
        )
        XCTAssertFalse(card.needsQuestion)
        XCTAssertEqual(card.object, "金边客户报告")
        XCTAssertTrue(card.executableGoal.contains("假设"))
        XCTAssertFalse(card.evidence.isEmpty)
    }

    func testHighRiskTieAsksOneQuestion() {
        let card = NexusIntentCompiler.compile(
            "把那个删掉",
            files: ["客户名单.txt", "客户备份.txt"]
        )
        XCTAssertEqual(card.risk, .high)
        XCTAssertTrue(card.needsQuestion)
        XCTAssertNotNil(card.question)
    }

    func testClearRequestDoesNotInventAssumption() {
        let card = NexusIntentCompiler.compile("计算 12 乘 3")
        XCTAssertFalse(card.needsQuestion)
        XCTAssertNil(card.assumption)
        XCTAssertEqual(card.risk, .low)
    }
}
