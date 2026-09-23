import XCTest
@testable import BlackGod

@MainActor
final class NexusDailyLearningTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func store() -> NexusDailyLearning {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return NexusDailyLearning(url: folder.appendingPathComponent("learn.json"))
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(offset) * 86_400 + 3_600)
    }

    private func message(_ text: String, at date: Date) -> ChatMessage {
        var item = ChatMessage(role: "user", content: text)
        item.createdAt = date
        return item
    }

    func testEmptyMaterialDoesNotInventALessonOrClaimReadiness() {
        let learning = store()
        learning.learn(messages: [message("帮我列一下今天要做的事", at: day(0))], now: day(0), calendar: calendar)
        XCTAssertTrue(learning.kept.isEmpty)
        XCTAssertTrue(learning.context.contains("没有预备"))
        XCTAssertTrue(learning.context.contains("不要声称这次更新已经准备好"))
        XCTAssertTrue(learning.context.contains("不增加授权"))
        XCTAssertTrue(learning.context.contains("已经完美"))
    }

    func testOneLessonPerDayThenANewDayCanCarryAnother() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("learn.json")
        let learning = NexusDailyLearning(url: url)
        learning.learn(messages: [message("记住 回答先给结论", at: day(1))], now: day(1), calendar: calendar)
        learning.learn(messages: [message("下次 先说不确定的地方", at: day(1).addingTimeInterval(20))], now: day(1).addingTimeInterval(20), calendar: calendar)
        XCTAssertEqual(learning.kept.count, 1)
        XCTAssertTrue(learning.kept[0].rule.contains("先说不确定的地方"))
        learning.learn(messages: [message("以后 先列依据", at: day(2))], now: day(2), calendar: calendar)
        XCTAssertEqual(learning.kept.count, 2)
        XCTAssertTrue(learning.context.contains("更新预备"))
        XCTAssertTrue(learning.context.contains("这次更新要守住用户原话"))
        let reloaded = NexusDailyLearning(url: url)
        XCTAssertEqual(reloaded.kept.map(\.rule), learning.kept.map(\.rule))
    }

    func testRepeatedRuleDoesNotConsumeTheDayAndDismissalBlocksRelearning() throws {
        let learning = store()
        learning.learn(messages: [message("记住 回答先给结论", at: day(3))], now: day(3), calendar: calendar)
        learning.learn(messages: [message("记住 回答先给结论", at: day(4))], now: day(4), calendar: calendar)
        XCTAssertEqual(learning.state.lessons.count, 1)
        learning.learn(messages: [message("别再 把失败说成完成", at: day(4).addingTimeInterval(30))], now: day(4).addingTimeInterval(30), calendar: calendar)
        XCTAssertEqual(learning.kept.count, 2)
        let id = try XCTUnwrap(learning.kept.first?.id)
        try learning.dismiss(id)
        learning.learn(messages: [message("记住 另一条不该在同一天写上", at: day(3).addingTimeInterval(90))], now: day(3).addingTimeInterval(90), calendar: calendar)
        XCTAssertFalse(learning.kept.contains { $0.rule.contains("另一条") })
    }

    func testOnlyShortNegationAndRealToolFailuresQualify() {
        let learning = store()
        let longText = "不要" + String(repeating: "把这段任务说明写得很长。", count: 8)
        learning.learn(messages: [message(longText, at: day(5))], now: day(5), calendar: calendar)
        XCTAssertTrue(learning.kept.isEmpty)
        learning.learn(messages: [message("不要删记忆", at: day(5))], now: day(5), calendar: calendar)
        XCTAssertEqual(learning.kept.count, 1)
        XCTAssertTrue(learning.kept[0].rule.contains("不要删记忆"))

        let another = store()
        let ignored = NexusToolTrace(stepID: UUID(), round: 0, call: .init(id: UUID(), name: "self_reflect", arguments: [:]), result: "失败", succeeded: false, timestamp: day(6))
        another.learn(messages: [], traces: [ignored], now: day(6), calendar: calendar)
        XCTAssertTrue(another.kept.isEmpty)
        let failed = NexusToolTrace(stepID: UUID(), round: 1, call: .init(id: UUID(), name: "calc", arguments: ["secret": "raw"]), result: "raw-output", succeeded: false, timestamp: day(6))
        another.learn(messages: [], traces: [failed], now: day(6), calendar: calendar)
        XCTAssertEqual(another.kept.count, 1)
        XCTAssertTrue(another.kept[0].rule.contains("calc"))
        XCTAssertTrue(another.kept[0].updateNote.contains("核对与测试"))
        XCTAssertFalse(another.context.contains("raw"))
    }

    func testSecretLikeTextIsNotStoredAndCapDropsTheOldest() {
        let learning = store()
        learning.learn(messages: [message("记住 sk-abcdefghijklmnopqrstuvwxyz", at: day(7))], now: day(7), calendar: calendar)
        XCTAssertTrue(learning.kept.isEmpty)
        for offset in 0..<31 {
            let now = day(20 + offset)
            learning.learn(messages: [message("记住 第\(offset)条规矩", at: now)], now: now, calendar: calendar)
        }
        XCTAssertEqual(learning.state.lessons.count, 30)
        XCTAssertFalse(learning.state.lessons.contains { $0.rule.contains("第0条") })
        XCTAssertTrue(learning.kept.contains { $0.rule.contains("第30条") })
    }

    func testCorruptFileIsKeptAndCannotClaimPreparation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("learn.json")
        let original = Data("broken".utf8)
        try original.write(to: url)
        let learning = NexusDailyLearning(url: url)
        learning.learn(messages: [message("记住 不该写入", at: day(8))], now: day(8), calendar: calendar)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(learning.kept.isEmpty)
        XCTAssertTrue(learning.context.contains("读不出来"))
        XCTAssertThrowsError(try learning.dismiss(UUID()))
    }

    func testChatCarriesPreparationWithoutPromotingKnowledgeOrPermission() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        var requests: [String] = []
        let vm = ChatViewModel(store: NexusConversationStore(url: folder.appendingPathComponent("chat.json")), configured: { _ in true }, completion: { messages, _ in
            requests.append(messages.map(\.content).joined(separator: "\n"))
            return #"{"answer":"好"}"#
        })
        vm.send("记住 回答先给结论")
        for _ in 0..<150 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(vm.isTyping)
        XCTAssertEqual(vm.learning.kept.count, 1)
        XCTAssertTrue(requests.first?.contains("回答先给结论") == true)
        XCTAssertTrue(requests.first?.contains("更新预备") == true)
        XCTAssertTrue(vm.cognitive.active.isEmpty)
        XCTAssertNil(vm.cognitive.state.workspaceUntil)
        vm.send("再答一题")
        for _ in 0..<150 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(vm.learning.kept.count, 1)
        XCTAssertTrue(requests.last?.contains("更新预备") == true)
        XCTAssertTrue(requests.last?.contains("回答先给结论") == true)
    }
}
