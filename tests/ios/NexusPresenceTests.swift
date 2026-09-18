import XCTest
@testable import BlackGod

final class NexusPresenceTests: XCTestCase {
    func testTypingIsWorkingBreath() {
        let snap = NexusPresence.snapshot(
            isTyping: true, canResume: true, resumeGoal: "未完成",
            practiceDue: true, practiceRunning: false, lastUser: "上次", pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(snap.mood, "处理中")
        XCTAssertEqual(snap.action, .none)
        XCTAssertEqual(snap.breath, 0.9)
    }

    func testUnfinishedTaskBeatsPracticeAndHistory() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "把账单拆成三步",
            practiceDue: true, practiceRunning: false, lastUser: "昨天的话", pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "可续")
        XCTAssertEqual(snap.action, .resume)
        XCTAssertEqual(snap.actionTitle, "继续未完成")
        XCTAssertEqual(snap.thread, "把账单拆成三步")
        XCTAssertEqual(snap.breath, 1.6)
    }

    func testDuePracticeFindsWorkWithoutWaiting() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: nil, pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "该练")
        XCTAssertEqual(snap.action, .practice)
        XCTAssertEqual(snap.nextWork, "到点该练技能")
    }

    func testLastTalkKeepsContinuity() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: false, practiceRunning: false,
            lastUser: "用枢语造一个关于锚点的词", pulseNote: "昼 · 枢形凝起"
        )
        XCTAssertEqual(snap.mood, "在场")
        XCTAssertEqual(snap.action, .continueLast)
        XCTAssertTrue(snap.nextWork.contains("接着上次"))
        XCTAssertEqual(snap.breath, 2.4)
    }

    func testIdlePulseIsPresenceNotReadyDeadState() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: false, practiceRunning: false, lastUser: nil, pulseNote: "夜 · 奥姿凝起"
        )
        XCTAssertEqual(snap.mood, "在场")
        XCTAssertEqual(snap.action, .pulse)
        XCTAssertEqual(snap.nextWork, "此刻 夜 · 奥姿凝起")
        XCTAssertNotEqual(snap.mood, "就绪")
    }
}
