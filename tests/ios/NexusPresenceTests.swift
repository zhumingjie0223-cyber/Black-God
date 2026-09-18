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
        XCTAssertEqual(snap.nextWork, "正在做事")
    }

    func testWorkingSurfacesLiveStatus() {
        let snap = NexusPresence.snapshot(
            isTyping: true, canResume: false, resumeGoal: "算账",
            practiceDue: false, practiceRunning: false, lastUser: "算账",
            liveStatus: "正在调用计算", pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "处理中")
        XCTAssertEqual(snap.nextWork, "正在调用计算")
        XCTAssertEqual(snap.thread, "算账")
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
        XCTAssertEqual(snap.nextWork, "刚停，进度还在")
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

    func testAnsweredSettlesInsteadOfSnappingToIdle() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: false, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(snap.mood, "刚歇")
        XCTAssertEqual(snap.action, .followUp)
        XCTAssertEqual(snap.actionTitle, "接着问")
        XCTAssertEqual(snap.thread, "结果是 36")
        XCTAssertEqual(snap.nextWork, "还在 · 夜 · 奥形凝起")
        XCTAssertEqual(snap.breath, 3.2)
        XCTAssertNotEqual(snap.mood, "就绪")
    }

    func testUnfinishedBeatsAfterglow() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            lastReply: "半截", answered: true, pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "可续")
        XCTAssertEqual(snap.action, .resume)
    }

    @MainActor
    func testUserStopDoesNotPretendToBeAnError() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in true }, completion: { _, _ in
            try await Task.sleep(for: .seconds(5))
            return "不该出现"
        })
        vm.send("先停一下")
        await Task.yield()
        vm.cancel()
        XCTAssertFalse(vm.isTyping)
        XCTAssertNil(vm.lastError)
        XCTAssertEqual(vm.statusHint, "已停止，进度还在")
        XCTAssertTrue(vm.canResume)
        XCTAssertEqual(vm.presence.mood, "可续")
        XCTAssertEqual(vm.presence.nextWork, "刚停，进度还在")
    }
}
