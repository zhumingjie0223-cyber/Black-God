import XCTest
@testable import BlackGod

final class NexusPresenceTests: XCTestCase {
    func testVisibleMoodsStayFewAndReadable() {
        XCTAssertEqual(NexusPresence.moods, ["在场", "在听", "在做", "接得上", "该练"])
        for name in ["侧耳", "偎着", "挨着", "依着", "靠着", "衔着", "顿笔", "惦记", "收笔", "落定", "开口", "应声", "处理中", "可续", "看着", "还在", "等下文", "让开", "守着", "陪着", "候着", "醒着", "刚歇", "余韵", "跟上"] {
            XCTAssertFalse(NexusPresence.moods.contains(name), name)
        }
    }

    func testTypingIsWorkingBreath() {
        let snap = NexusPresence.snapshot(
            isTyping: true, canResume: true, resumeGoal: "未完成",
            practiceDue: true, practiceRunning: false, lastUser: "上次", pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(snap.mood, "在做")
        XCTAssertEqual(snap.stance, "answering")
        XCTAssertEqual(snap.action, .none)
        XCTAssertEqual(snap.breath, 0.6)
        XCTAssertEqual(snap.nextWork, "听见了")
        let begin = NexusPresence.snapshot(
            isTyping: true, canResume: false, resumeGoal: "算账",
            practiceDue: false, practiceRunning: false, lastUser: "算账",
            liveStatus: "正在理解任务", pulseNote: nil
        )
        XCTAssertEqual(begin.mood, "在做")
        XCTAssertEqual(begin.nextWork, "听见了")
    }

    func testWorkingSurfacesLiveStatus() {
        let snap = NexusPresence.snapshot(
            isTyping: true, canResume: false, resumeGoal: "算账",
            practiceDue: false, practiceRunning: false, lastUser: "算账",
            liveStatus: "正在调用计算", pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "在做")
        XCTAssertEqual(snap.nextWork, "正在调用计算")
        XCTAssertEqual(snap.thread, "算账")
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let hearing = NexusPresence.snapshot(
            isTyping: true, canResume: false, resumeGoal: "算账",
            practiceDue: false, practiceRunning: false, lastUser: "算账",
            liveStatus: "正在调用计算", now: t0, typingAt: t0, pulseNote: nil
        )
        XCTAssertEqual(hearing.mood, "在做")
        XCTAssertEqual(hearing.nextWork, "听见了")
        let working = NexusPresence.snapshot(
            isTyping: true, canResume: false, resumeGoal: "算账",
            practiceDue: false, practiceRunning: false, lastUser: "算账",
            liveStatus: "正在调用计算", now: t0.addingTimeInterval(1), typingAt: t0, pulseNote: nil
        )
        XCTAssertEqual(working.mood, "在做")
        XCTAssertEqual(working.stance, "working")
        XCTAssertEqual(working.nextWork, "正在调用计算")
    }

    func testSpeakingSurfacesLiveSpeech() {
        let snap = NexusPresence.snapshot(
            isTyping: true, canResume: false, resumeGoal: "算账",
            practiceDue: false, practiceRunning: false, lastUser: "算账",
            liveStatus: "正在调用计算", liveSpeech: "先列出科目", pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "在做")
        XCTAssertEqual(snap.stance, "speaking")
        XCTAssertEqual(snap.nextWork, "先列出科目")
        XCTAssertEqual(snap.thread, "算账")
        XCTAssertEqual(snap.breath, 0.7)
        XCTAssertEqual(snap.action, .none)
    }

    func testUnfinishedTaskBeatsPracticeAndHistory() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "把账单拆成三步",
            practiceDue: true, practiceRunning: false, lastUser: "昨天的话", pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "接得上")
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
        XCTAssertEqual(snap.mood, "接得上")
        XCTAssertEqual(snap.action, .continueLast)
        XCTAssertTrue(snap.nextWork.contains("接着上次"))
        XCTAssertEqual(snap.breath, 2.0)
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
        XCTAssertGreaterThan(snap.breath, 1)
    }

    func testAnsweredStaysConnectableWithoutMicroMoods() {
        let answeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: false, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(snap.mood, "接得上")
        XCTAssertEqual(snap.stance, "exhaling")
        XCTAssertEqual(snap.action, .followUp)
        XCTAssertEqual(snap.actionTitle, "接着问")
        XCTAssertEqual(snap.thread, "结果是 36")
        XCTAssertEqual(snap.nextWork, "刚说到这儿")
        XCTAssertEqual(snap.breath, 1.0)
        let later = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: false, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(20), pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(later.mood, "接得上")
        XCTAssertEqual(later.action, .followUp)
        XCTAssertTrue(["还等你接下句", "还在 · 夜 · 奥形凝起"].contains(later.nextWork))
        XCTAssertNotEqual(later.mood, "侧耳")
        XCTAssertNotEqual(later.mood, "偎着")
        let echo = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: false, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(200), pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(echo.mood, "接得上")
        XCTAssertEqual(echo.stance, "echoing")
        XCTAssertEqual(echo.action, .followUp)
        let faded = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: false, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(1000), pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(faded.mood, "接得上")
        XCTAssertEqual(faded.action, .continueLast)
        let practiced = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: true, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(1000), pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(practiced.mood, "该练")
    }

    func testUnfinishedBeatsAfterglow() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            lastReply: "半截", answered: true, pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "接得上")
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
        XCTAssertEqual(snap.stance, "following")
        XCTAssertEqual(snap.nextWork, "你接着说")
        XCTAssertEqual(snap.thread, "接着问账单")
        XCTAssertEqual(snap.action, .none)
        XCTAssertEqual(snap.breath, 1.05)
    }

    func testUnfinishedBeatsListening() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            draft: "新的话", pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "接得上")
        XCTAssertEqual(snap.action, .resume)
    }

    func testFreshAnswerBeatsPractice() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: true, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, pulseNote: nil
        )
        XCTAssertEqual(snap.mood, "接得上")
        XCTAssertEqual(snap.action, .followUp)
        XCTAssertEqual(snap.nextWork, "刚说到这儿")
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
        XCTAssertEqual(vm.presence.mood, "接得上")
        XCTAssertEqual(vm.presence.nextWork, "刚停，进度还在")
    }

    @MainActor
    func testFollowUpKeepsLastTalk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in true }, completion: { _, _ in "先列出科目" })
        vm.send("把账单拆成三步")
        for _ in 0..<100 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(vm.presence.mood, "接得上")
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
        XCTAssertEqual(vm.presence.mood, "在听")
        XCTAssertEqual(vm.presence.nextWork, "你收回去了")
        vm.attend(false)
        XCTAssertEqual(vm.presence.mood, "在听")
    }

    func testAttendingEmptyIsPresent() {
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            attending: true, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(snap.mood, "在场")
        XCTAssertEqual(snap.stance, "watching")
        XCTAssertEqual(snap.nextWork, "等你开口 · 夜 · 奥形凝起")
        XCTAssertEqual(snap.action, .none)
        XCTAssertEqual(snap.breath, 1.4)
    }

    func testAttendingAfterAnswerCarriesTheThread() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, answeredAt: t0,
            now: t0.addingTimeInterval(10), attending: true, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(snap.mood, "接得上")
        XCTAssertEqual(snap.stance, "carrying")
        XCTAssertEqual(snap.nextWork, "还接着刚才")
        XCTAssertEqual(snap.thread, "刚答完")
        XCTAssertEqual(snap.action, .followUp)
        XCTAssertEqual(snap.actionTitle, "接着问")
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
        XCTAssertEqual(back.mood, "接得上")
        XCTAssertEqual(back.stance, "exhaling")
        XCTAssertEqual(back.nextWork, "刚说到这儿")
        XCTAssertEqual(back.action, .followUp)
        let notice = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: true, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(10), noticedAt: answeredAt.addingTimeInterval(9),
            pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(notice.mood, "接得上")
        XCTAssertEqual(notice.nextWork, "你回来了 · 夜 · 奥形凝起")
        let unfinished = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            now: answeredAt.addingTimeInterval(2), noticedAt: answeredAt, pulseNote: nil
        )
        XCTAssertEqual(unfinished.mood, "接得上")
        XCTAssertEqual(unfinished.action, .resume)
        let faded = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算 12*3",
            practiceDue: false, practiceRunning: false, lastUser: "算 12*3",
            lastReply: "结果是 36", answered: true, answeredAt: answeredAt,
            now: answeredAt.addingTimeInterval(20), noticedAt: answeredAt,
            pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(faded.mood, "接得上")
        XCTAssertEqual(faded.action, .followUp)
    }

    @MainActor
    func testNoticeAfterLeaveKeepsBody() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in false })
        vm.leave()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        vm.notice(now: t0)
        XCTAssertEqual(vm.presence.mood, "在场")
        XCTAssertEqual(vm.presence.stance, "noticing")
        XCTAssertTrue(vm.presence.nextWork.contains("你回来了"))
        vm.attend(true, now: t0)
        XCTAssertEqual(vm.presence.mood, "在场")
        vm.attend(false, now: t0.addingTimeInterval(1))
        XCTAssertEqual(vm.presence.mood, "在场")
        XCTAssertTrue(vm.presence.nextWork.contains("你回来了"))
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
        XCTAssertEqual(listening.nextWork, "你接着说")
        let hitch = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, now: t0.addingTimeInterval(2),
            draft: "接着问账单", attending: true, heardAt: t0, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(hitch.mood, "在听")
        XCTAssertEqual(hitch.stance, "hitching")
        XCTAssertEqual(hitch.nextWork, "等你写完")
        XCTAssertEqual(hitch.thread, "接着问账单")
        XCTAssertEqual(hitch.action, .none)
        let hold = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, now: t0.addingTimeInterval(2),
            draft: "接着问账单", attending: false, heardAt: t0, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(hold.mood, "在听")
        XCTAssertEqual(hold.stance, "holding")
        XCTAssertEqual(hold.nextWork, "你写到这儿了")
        let unfinished = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            now: t0.addingTimeInterval(2), draft: "新的话", attending: false, heardAt: t0,
            pulseNote: nil
        )
        XCTAssertEqual(unfinished.mood, "接得上")
        XCTAssertEqual(unfinished.action, .resume)
    }

    @MainActor
    func testHearPauseAndLeaveKeepsDraft() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in false })
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        vm.hear("接着问", now: t0)
        XCTAssertEqual(vm.presence.mood, "在听")
        XCTAssertEqual(vm.presence.nextWork, "你写到这儿了")
        vm.attend(true, now: t0)
        XCTAssertEqual(vm.presence.mood, "在听")
        vm.awaken(now: t0.addingTimeInterval(2))
        XCTAssertEqual(vm.presence.mood, "在听")
        XCTAssertEqual(vm.presence.nextWork, "等你写完")
        vm.attend(false, now: t0.addingTimeInterval(3))
        XCTAssertEqual(vm.presence.mood, "在听")
    }

    func testClearedDraftRetractsThenWatches() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let retract = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, now: t0.addingTimeInterval(1),
            attending: true, retractedAt: t0, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(retract.mood, "在听")
        XCTAssertEqual(retract.stance, "retracting")
        XCTAssertEqual(retract.nextWork, "你收回去了")
        XCTAssertEqual(retract.action, .none)
        let restore = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, now: t0.addingTimeInterval(1),
            attending: true, retractedAt: t0, retractedDraft: "接着问账单", pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(restore.mood, "在听")
        XCTAssertEqual(restore.action, .restoreDraft)
        XCTAssertEqual(restore.actionTitle, "还给你")
        XCTAssertEqual(restore.thread, "接着问账单")
        let watching = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, answeredAt: t0.addingTimeInterval(-10),
            now: t0.addingTimeInterval(5), attending: true, retractedAt: t0, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(watching.mood, "接得上")
        XCTAssertEqual(watching.nextWork, "还接着刚才")
        let faded = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: nil,
            practiceDue: true, practiceRunning: false, lastUser: "上次",
            lastReply: "刚答完", answered: true, answeredAt: t0.addingTimeInterval(-1000),
            now: t0.addingTimeInterval(5), attending: true, retractedAt: t0, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(faded.mood, "在场")
        let unfinished = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            now: t0.addingTimeInterval(1), retractedAt: t0, pulseNote: nil
        )
        XCTAssertEqual(unfinished.mood, "接得上")
        XCTAssertEqual(unfinished.action, .resume)
        let typing = NexusPresence.snapshot(
            isTyping: true, canResume: false, resumeGoal: "算账",
            practiceDue: false, practiceRunning: false, lastUser: "算账",
            now: t0.addingTimeInterval(1), retractedAt: t0, pulseNote: nil
        )
        XCTAssertEqual(typing.mood, "在做")
    }

    @MainActor
    func testHearClearRetractsWithoutSending() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in false })
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        vm.hear("接着问", now: t0)
        vm.attend(true, now: t0)
        vm.hear("接着", now: t0.addingTimeInterval(0.4))
        vm.hear("接", now: t0.addingTimeInterval(0.8))
        vm.hear("", now: t0.addingTimeInterval(1))
        XCTAssertEqual(vm.presence.mood, "在听")
        XCTAssertEqual(vm.presence.nextWork, "你收回去了")
        XCTAssertEqual(vm.presence.action, .restoreDraft)
        vm.actOnPresence()
        XCTAssertEqual(vm.composerPrefill, "接着问")
        vm.hear("接着问", now: t0.addingTimeInterval(1.5))
        XCTAssertEqual(vm.presence.mood, "在听")
        vm.hear("", now: t0.addingTimeInterval(2))
        vm.awaken(now: t0.addingTimeInterval(7))
        XCTAssertEqual(vm.presence.mood, "在场")
    }

    @MainActor
    func testSpeakingFollowsLiveOutput() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in true }, completion: { _, _ in
            try await Task.sleep(for: .seconds(5))
            return "不该出现"
        })
        vm.send("先说")
        await Task.yield()
        XCTAssertEqual(vm.presence.mood, "在做")
        vm.live.append(.output, "先列出科目")
        XCTAssertEqual(vm.presence.mood, "在做")
        XCTAssertEqual(vm.presence.nextWork, "先列出科目")
        vm.cancel()
        XCTAssertEqual(vm.presence.mood, "接得上")
    }

    func testSettleBeatsWatchingThenFades() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算账",
            practiceDue: true, practiceRunning: false, lastUser: "算账",
            lastReply: "先列出科目", answered: true, answeredAt: t0,
            now: t0.addingTimeInterval(2), attending: true, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(snap.mood, "接得上")
        XCTAssertEqual(snap.nextWork, "刚说到这儿")
        let carrying = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算账",
            practiceDue: true, practiceRunning: false, lastUser: "算账",
            lastReply: "先列出科目", answered: true, answeredAt: t0,
            now: t0.addingTimeInterval(7), attending: true, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(carrying.mood, "接得上")
        XCTAssertEqual(carrying.nextWork, "还接着刚才")
        XCTAssertEqual(carrying.action, .followUp)
        let later = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算账",
            practiceDue: true, practiceRunning: false, lastUser: "算账",
            lastReply: "先列出科目", answered: true, answeredAt: t0,
            now: t0.addingTimeInterval(48), attending: true, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(later.mood, "接得上")
        XCTAssertNotEqual(later.mood, "侧耳")
        XCTAssertNotEqual(later.mood, "偎着")
        let watching = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算账",
            practiceDue: true, practiceRunning: false, lastUser: "算账",
            lastReply: "先列出科目", answered: true, answeredAt: t0,
            now: t0.addingTimeInterval(1000), attending: true, pulseNote: "夜 · 奥形凝起"
        )
        XCTAssertEqual(watching.mood, "在场")
    }

    func testFollowingKeepsTheThreadWhileDrafting() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let follow = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算账",
            practiceDue: true, practiceRunning: false, lastUser: "算账",
            lastReply: "先列出科目", answered: true, answeredAt: t0,
            now: t0.addingTimeInterval(20), draft: "那下一步", attending: true, pulseNote: nil
        )
        XCTAssertEqual(follow.mood, "在听")
        XCTAssertEqual(follow.stance, "following")
        XCTAssertEqual(follow.nextWork, "你接着说")
        XCTAssertEqual(follow.thread, "那下一步")
        XCTAssertEqual(follow.action, .none)
        let hitch = NexusPresence.snapshot(
            isTyping: false, canResume: false, resumeGoal: "算账",
            practiceDue: false, practiceRunning: false, lastUser: "算账",
            lastReply: "先列出科目", answered: true, answeredAt: t0,
            now: t0.addingTimeInterval(20), draft: "那下一步", attending: true,
            heardAt: t0.addingTimeInterval(18), pulseNote: nil
        )
        XCTAssertEqual(hitch.mood, "在听")
        XCTAssertEqual(hitch.nextWork, "等你写完")
        let unfinished = NexusPresence.snapshot(
            isTyping: false, canResume: true, resumeGoal: "未完成",
            practiceDue: false, practiceRunning: false, lastUser: "未完成",
            lastReply: "半截", answered: true, answeredAt: t0,
            now: t0.addingTimeInterval(16), attending: true, pulseNote: nil
        )
        XCTAssertEqual(unfinished.mood, "接得上")
        XCTAssertEqual(unfinished.action, .resume)
    }
}
