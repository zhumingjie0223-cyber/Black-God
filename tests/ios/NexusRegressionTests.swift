import XCTest
@testable import BlackGod

final class NexusRegressionTests: XCTestCase {
    func testApplicationResourcesArePackaged() throws {
        let bundle = Bundle(for: ChatViewModel.self)
        XCTAssertNotNil(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "zh-Hans.lproj"))
        XCTAssertNotNil(bundle.object(forInfoDictionaryKey: "UILaunchScreen"))
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, "1.2.0")
    }

    func testCalculatorRejectsMalformedExpressions() async throws {
        let calculator = NexusCalculatorTool()
        let value = try await calculator.run(arguments: "(3 + 4) * -2 + .5")
        XCTAssertEqual(value, "-13.5")
        for input in ["", "1/0", "(1+2", "1..2", "1+", "2foo", String(repeating: "(", count: 70) + "1", String(repeating: "9", count: 400)] {
            let result = await calculator.execute(NexusToolCall(id: UUID(), name: "calc", arguments: ["expression": input]))
            XCTAssertFalse(result.succeeded, input)
        }
    }

    func testToolResponsesPreserveOrdinaryCode() {
        let text = "说明\n```json\n{\"name\":\"calc\",\"arguments\":{\"expression\":\"2+2\"}}\n```\n```json\n{\"answer\":4}\n```\n结束"
        let response = NexusToolCallParser.response(from: text)
        XCTAssertEqual(response.calls.count, 1)
        XCTAssertEqual(response.calls.first?.name, "calc")
        XCTAssertTrue(response.text.contains("\"answer\":4"))
        XCTAssertFalse(response.text.contains("expression"))
        XCTAssertTrue(response.text.hasSuffix("结束"))
    }

    func testRequestsDoNotAdvertiseDisconnectedTools() throws {
        for model in NexusModelCatalog.entries {
            let data = try NexusProviderRequestBuilder.body(model: model, messages: [ChatMessage(role: "user", content: "你好")])
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(body["tools"])
            XCTAssertEqual(body["model"] as? String, model.modelID)
        }
        XCTAssertEqual(NexusModelCatalog.entry(for: "claude-sonnet-4-6").modelID, "claude-sonnet-4-6")
    }

    func testConversationPersistence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = NexusConversationStore(url: url)
        XCTAssertTrue(try store.load().isEmpty)
        try store.save([ChatMessage(role: "user", content: "保存这条对话")])
        XCTAssertEqual(try store.load().first?.content, "保存这条对话")
    }

    @MainActor
    func testToolRoundTrip() async {
        var prompts: [String] = []
        let executor = NexusExecutor(model: { prompt in
            prompts.append(prompt)
            if prompts.count == 1 { return "{\"name\":\"calc\",\"arguments\":{\"expression\":\"2+2\"}}" }
            return "计算结果是4"
        })
        _ = await executor.run(goal: "计算结果")
        XCTAssertEqual(executor.toolTraces.count, 1)
        XCTAssertEqual(executor.toolTraces.first?.result, "4")
        XCTAssertTrue(prompts[1].contains("=> 4"))
    }

    @MainActor
    func testCancelledRunCannotOverwriteNextRun() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var requests: [[ChatMessage]] = []
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in true }, completion: { messages, _ in
            requests.append(messages)
            if requests.count == 1 { try await Task.sleep(for: .seconds(5)) }
            return "第二次回答完成"
        })
        vm.send("第一次回答")
        await Task.yield()
        vm.cancel()
        vm.send("第二次回答")
        for _ in 0..<100 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(vm.isTyping)
        XCTAssertNil(vm.lastError)
        XCTAssertEqual(vm.messages.last?.content, "第二次回答完成")
        XCTAssertEqual(vm.runtime.runState, .completed)
        let saved = try NexusAgentCheckpointStore(url: url.deletingPathExtension().appendingPathExtension("agent.json")).load()
        XCTAssertEqual(saved?.goal, "第二次回答")
        XCTAssertEqual(saved?.state, .answered)
    }

    @MainActor
    func testRetryDoesNotDuplicateUserMessage() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var attempts = 0
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in true }, completion: { _, _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return "已恢复回答"
        })
        vm.send("回答")
        for _ in 0..<100 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(vm.canRetry)
        vm.retry()
        for _ in 0..<100 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(vm.messages.filter { $0.role == "user" }.count, 1)
        XCTAssertEqual(vm.messages.last?.content, "已恢复回答")
        XCTAssertNil(vm.lastError)
    }

    @MainActor
    func testFollowUpIncludesPreviousConversation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("chat.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var requests: [[ChatMessage]] = []
        let vm = ChatViewModel(store: NexusConversationStore(url: url), configured: { _ in true }, completion: { messages, _ in
            requests.append(messages)
            return "苹果水果说明"
        })
        vm.send("苹果水果")
        for _ in 0..<100 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        vm.send("苹果水果继续")
        for _ in 0..<100 where vm.isTyping { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(requests.last?.contains(where: { $0.role == "assistant" && $0.content == "苹果水果说明" }) == true)
        XCTAssertEqual(vm.messages.filter { $0.role == "user" }.count, 2)
    }
}
