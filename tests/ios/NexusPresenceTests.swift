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

    func testDraftIsListeningBreath() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: false, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, draft: "接着问账单", attending: true,
            pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(snap.mood, "在听")
        XCTAssertEqual(snap.stance, "listening")
        XCTAssertEqual(snap.nextWork, "你正在说")
        XCTAssertEqual(snap.thread, "接着问账单")
        XCTAssertEqual(snap.action, .none)
        XCTAssertEqual(snap.breath, 1.1)
    }

    func testUnfinishedBeatsListening() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            draft: "新的话", pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "可续")
        XCTAssertEqual(snap.action, .resume)
    }

    func testAfterglowFadesToEchoThenPresence() {
        let answeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let echo = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: false, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(200), pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(echo.mood, "余韵")
        XCTAssertEqual(echo.stance, "echoing")
        XCTAssertEqual(echo.action, .followUp)
        XCTAssertEqual(echo.nextWork, "余音 · 夜 · 奥形凝起")
        XCTAssertEqual(echo.breath, 2.2)
        let faded = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: false, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(1000), pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(faded.mood, "在场")
        XCTAssertEqual(faded.action, .continueLast)
        let practiced = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: true, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(1000), pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(practiced.mood, "该练")
    }

    func testFreshAnswerBeatsPractice() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: true, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "刚歇")
        XCTAssertEqual(snap.action, .followUp)
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

    @MainActor
    func testFollowUpKeepsLastTalk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in true }, completion: { _, _ in "先列出科目" })
        vm.send("把账单拆成三步")
        for _ in 0..<100 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(vm.presence.mood, "刚歇")
        vm.actOnPresence()
        XCTAssertEqual(vm.composerPrefill, "接着「把账单拆成三步」：")
    }

    @MainActor
    func testHearAndFollowUpKeepTheThread() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in false })
        vm.messages = [
            ChatMessage(role: "user", content: "把账单拆成三步"),
            ChatMessage(role: "assistant", content: "先列出科目")
        ]
        vm.hear("接着问")
        vm.attend(true)
        XCTAssertEqual(vm.presence.mood, "在听")
        XCTAssertEqual(vm.presence.nextWork, "你正在说")
        vm.hear("")
        XCTAssertNotEqual(vm.presence.mood, "在听")
        XCTAssertTrue(["在场", "该练"].contains(vm.presence.mood))
    }

    func testAttendingEmptyIsWatching() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, attending: true, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(snap.mood, "看着")
        XCTAssertEqual(snap.stance, "watching")
        XCTAssertEqual(snap.nextWork, "等你开口 · 夜 · 奥形凝起")
        XCTAssertEqual(snap.action, .none)
        XCTAssertEqual(snap.breath, 1.4)
    }

    func testDraftBeatsWatching() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: false, practiceRunning: false, lastUser: "上次",
            draft: "新的话", attending: true, pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "在听")
        XCTAssertEqual(snap.action, .none)
    }

    func testNoticingBeatsAfterglowButNotUnfinished() {
        let answeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let back = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: true, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(4), noticedAt: answeredAt.addingTimeInterval(3),
            pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(back.mood, "还在")
        XCTAssertEqual(back.stance, "noticing")
        XCTAssertEqual(back.nextWork, "你回来了 · 夜 · 奥形凝起")
        XCTAssertEqual(back.action, .followUp)
        XCTAssertEqual(back.breath, 1.8)
        let unfinished = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            now: answeredAt.addingTimeInterval(2), noticedAt: answeredAt, pulseNote: nil
        )
        XCTAssertEqual(unfinished.mood, "可续")
        let faded = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: false, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(20), noticedAt: answeredAt,
            pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(faded.mood, "刚歇")
    }

    @MainActor
    func testNoticeAfterLeaveKeepsBody() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in false })
        vm.leave()
        vm.notice(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(vm.presence.mood, "还在")
        XCTAssertEqual(vm.presence.stance, "noticing")
        XCTAssertTrue(vm.presence.nextWork.contains("你回来了"))
        vm.attend(true)
        XCTAssertEqual(vm.presence.mood, "看着")
        vm.attend(false)
        XCTAssertEqual(vm.presence.mood, "还在")
    }

    func testPausedDraftIsHitchThenHold() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let listening = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, now: t0, draft: "接着问账单",
            attending: true, heardAt: t0, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(listening.mood, "在听")
        let hitch = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, now: t0.addingTimeInterval(2),
            draft: "接着问账单", attending: true, heardAt: t0, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(hitch.mood, "顿笔")
        XCTAssertEqual(hitch.stance, "hitching")
        XCTAssertEqual(hitch.nextWork, "等你写完")
        XCTAssertEqual(hitch.thread, "接着问账单")
        XCTAssertEqual(hitch.action, .none)
        XCTAssertEqual(hitch.breath, 1.5)
        let hold = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, now: t0.addingTimeInterval(2),
            draft: "接着问账单", attending: false, heardAt: t0, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(hold.mood, "惦记")
        XCTAssertEqual(hold.stance, "holding")
        XCTAssertEqual(hold.nextWork, "你写到这儿了")
        XCTAssertEqual(hold.breath, 2.0)
        let unfinished = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            now: t0.addingTimeInterval(2), draft: "新的话", attending: false, heardAt: t0,
            pulseNote: nil
        )
        XCTAssertEqual(unfinished.mood, "可续")
    }

    @MainActor
    func testHearPauseAndLeaveKeepsDraft() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in false })
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        vm.hear("接着问", now: t0)
        XCTAssertEqual(vm.presence.mood, "惦记")
        XCTAssertEqual(vm.presence.nextWork, "你写到这儿了")
        vm.attend(true, now: t0)
        XCTAssertEqual(vm.presence.mood, "在听")
        vm.awaken(now: t0.addingTimeInterval(2))
        XCTAssertEqual(vm.presence.mood, "顿笔")
        XCTAssertEqual(vm.presence.nextWork, "等你写完")
        vm.attend(false, now: t0.addingTimeInterval(3))
        XCTAssertEqual(vm.presence.mood, "惦记")
    }
}
