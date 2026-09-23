import XCTest
import SwiftUI
import UIKit
@testable import BlackGod

@MainActor
final class NexusLiveExecutionTests: XCTestCase {
    func testLiveDisplayIsBoundedRedactedAndRejectsLateOutput() {
        let live = NexusLiveExecution()
        live.begin(goal: "test secret-value", redacting: "secret-value")
        for _ in 0..<150 { live.append(.output, "secret-value " + String(repeating: "中", count: 1500)) }
        XCTAssertLessThanOrEqual(live.entries.count, 60)
        XCTAssertLessThanOrEqual(live.entries.map(\.text).reduce(0) { $0 + $1.count }, 16000)
        XCTAssertTrue(live.omitted)
        XCTAssertFalse(live.goal.contains("secret-value"))
        XCTAssertFalse(live.entries.contains { $0.text.contains("secret-value") })
        live.finish(.cancelled, message: "停止")
        let ids = live.entries.map(\.id)
        live.append(.output, "late output")
        live.phase("late phase")
        XCTAssertEqual(live.entries.map(\.id), ids)
        XCTAssertEqual(live.state, .cancelled)
        live.begin(goal: "next")
        XCTAssertTrue(live.entries.isEmpty)
        XCTAssertFalse(live.omitted)
    }
    func testCheckpointUpdatesDoNotDuplicateVisibleEvidence() {
        let live = NexusLiveExecution(); live.begin(goal: "计算")
        let trace = NexusToolTrace(stepID: UUID(), round: 1, call: NexusToolCall(id: UUID(), name: "calc", arguments: ["expression": "2+2"]), result: "4", succeeded: true, timestamp: Date())
        live.observe([trace]); live.observe([trace])
        XCTAssertEqual(live.entries.count, 1)
        XCTAssertTrue(live.entries[0].text.contains("4"))
    }
    func testLatestCommandSurvivesOutputEvictionAndResetsBetweenRuns() throws {
        let live = NexusLiveExecution()
        live.begin(goal: "输出大量内容", redacting: "private-token")
        live.append(.command, "printf private-token " + String(repeating: "x", count: 1500))
        let firstCommand = try XCTUnwrap(live.latestCommand)
        XCTAssertFalse(firstCommand.text.contains("private-token"))
        XCTAssertLessThanOrEqual(firstCommand.text.count, 1200)

        for line in 0..<150 { live.append(.output, "真实输出行 \(line)") }
        XCTAssertTrue(live.omitted)
        XCTAssertFalse(live.entries.contains { $0.id == firstCommand.id })
        XCTAssertEqual(live.latestCommand?.id, firstCommand.id)
        XCTAssertEqual(live.latestCommand?.text, firstCommand.text)

        live.append(.command, "printf next")
        XCTAssertNotEqual(live.latestCommand?.id, firstCommand.id)
        XCTAssertEqual(live.latestCommand?.text, "printf next")
        live.finish(.answered, message: "完成")
        live.append(.command, "late command")
        XCTAssertEqual(live.latestCommand?.text, "printf next")

        live.begin(goal: "新的任务")
        XCTAssertNil(live.latestCommand)
        XCTAssertTrue(live.entries.isEmpty)
        live.append(.command, "printf new-run")
        XCTAssertEqual(live.latestCommand?.text, "printf new-run")
        live.reset()
        XCTAssertNil(live.latestCommand)
    }
    func testFreshInstallEnablesEmbeddedExecutionButHonorsOptOut() throws {
        let suite = "blackgod.tests.execution." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(NexusLinuxTool.enabled(in: defaults))
        defaults.set(false, forKey: "blackgod.linux.modelTools")
        XCTAssertFalse(NexusLinuxTool.enabled(in: defaults))
        defaults.set(true, forKey: "blackgod.linux.modelTools")
        XCTAssertTrue(NexusLinuxTool.enabled(in: defaults))
    }
    func testActualLinuxOutputIsDeliveredBeforeProcessExit() async throws {
        let arrived = expectation(description: "streamed output")
        var output: [String] = []
        var ended = false
        let task = Task {
            defer { ended = true }
            return try await NexusLinuxRuntime.shared.execute(command: "printf 'first\\n'; sleep 2; printf 'last\\n'", workspace: UUID(), onOutput: { line, _ in
                output.append(line)
                if line == "first" { arrived.fulfill() }
            })
        }
        // A cold runtime may inspect the existing workspace before starting the process.
        // The assertion below still requires output to arrive while the command is running.
        await fulfillment(of: [arrived], timeout: 30)
        XCTAssertFalse(ended)
        let result = try await task.value
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(output, ["first", "last"])
    }
    func testOutputFloodHasBoundedCallbacksAndPreservesFinalResult() async throws {
        var lines: [String] = []
        let result = try await NexusLinuxRuntime.shared.execute(command: "seq 1 1000", workspace: UUID(), onOutput: { line, _ in lines.append(line) })
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(lines.count, 200)
        XCTAssertTrue(lines.last?.contains("展示上限") == true)
        XCTAssertTrue(result.output.hasSuffix("1000\n"))
    }
    func testUserGoalIsExecutedInternallyAndVisibleWithoutUserWritingCommands() async throws {
        let live = NexusLiveExecution(); live.begin(goal: "把三个商品价格求和")
        var tools = NexusToolRegistry()
        tools.register(NexusLinuxTool(workspace: UUID(), onStart: { live.append(.command, $0) }, onOutput: { line, error in live.append(error ? .error : .output, line) }, isEnabled: { true }))
        var replies = [#"{"steps":["计算价格"]}"#, #"{"name":"shell_execute","arguments":{"command":"printf '%s\\n' 12 18 9 | awk '{s+=$1} END {print s}'"}}"#, "三件商品合计39元。", #"{"passed":true,"issues":[]}"#]
        let engine = NexusReasoningEngine(tools: tools, model: { _ in replies.removeFirst() }, onCheckpoint: { live.observe($0.traces) }, onEvent: { live.phase($0) })
        let result = try await engine.run(goal: "把苹果12元、牛奶18元和面包9元求和")
        live.finish(.answered, message: "已生成答复")
        XCTAssertEqual(result.text, "三件商品合计39元。")
        XCTAssertTrue(live.entries.contains { $0.kind == .command })
        XCTAssertTrue(live.entries.contains { $0.kind == .output && $0.text == "39" })
        XCTAssertTrue(live.entries.contains { $0.kind == .result && $0.text.contains("exit_code=0") })
    }

    func testRealShellConversationRendersLiveOutputAndAnswerEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blackgod-chat-render-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NexusConversationStore(url: directory.appendingPathComponent("conversation.json"))
        var modelCalls = 0
        let vm = ChatViewModel(store: store, configured: { _ in false }, completion: { _, _ in
            modelCalls += 1
            XCTFail("视觉验收只运行内置 Shell，不应请求模型。")
            return ""
        })
        XCTAssertTrue(vm.messages.isEmpty)
        let goal = "帮我核对苹果 12 元、牛奶 18 元和面包 9 元，一共多少钱？"
        vm.messages = [ChatMessage(role: "user", content: goal)]
        vm.isTyping = true
        vm.live.begin(goal: goal)

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try XCTUnwrap(scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)
        let originalKeyWindow = scene.windows.first { $0.isKeyWindow }
        let appState = AppState()
        appState.isUnlocked = true
        appState.hapticEnabled = false
        let host = UIHostingController(rootView: ChatView(vm: vm)
            .environmentObject(appState)
            .preferredColorScheme(.dark)
            .tint(Color.bgGold)
            .background(Color.bgDark.ignoresSafeArea()))
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            originalKeyWindow?.makeKey()
            vm.cancel()
        }

        let firstOutput = expectation(description: "实际 Shell 的首段输出到达")
        var stdout: [String] = []
        var stderr: [String] = []
        var startedCommands: [String] = []
        var didReceiveFirstOutput = false
        var ended = false
        let command = "printf '开始核对采购金额\\n'; sleep 5; printf 'TOTAL=%s\\n' \"$((12 + 18 + 9))\"; printf '核对完成\\n'"
        // A stable test-only guest workspace avoids creating a new rootfs for every screenshot run.
        let workspace = try XCTUnwrap(UUID(uuidString: "51B91632-69AF-4E6E-947B-E388186694B2"))
        let tool = NexusLinuxTool(workspace: workspace, onStart: { script in
            startedCommands.append(script)
            vm.live.append(.command, script)
        }, onOutput: { line, isError in
            if isError { stderr.append(line) } else { stdout.append(line) }
            vm.live.append(isError ? .error : .output, line)
            if !isError, line == "开始核对采购金额", !didReceiveFirstOutput {
                didReceiveFirstOutput = true
                firstOutput.fulfill()
            }
        }, onStatus: { vm.live.phase($0) }, isEnabled: { true })
        let call = NexusToolCall(id: UUID(), name: tool.name, arguments: ["command": command, "timeout": "20"])
        // Use the production tool -> runtime path, including its real start/status/output callbacks.
        let execution = Task {
            defer { ended = true }
            return await tool.execute(call)
        }
        defer { execution.cancel() }

        await fulfillment(of: [firstOutput], timeout: 30)
        if didReceiveFirstOutput, !ended {
            XCTAssertEqual(startedCommands, [command])
            XCTAssertEqual(stdout, ["开始核对采购金额"])
            XCTAssertTrue(NexusLinuxRuntime.shared.isExecuting)
            XCTAssertEqual(vm.live.state, .running)
            XCTAssertEqual(vm.live.latestCommand?.text, command)
            await attachConversationSnapshot(window, name: "会话-Shell实时输出")
            XCTAssertFalse(ended, "直播截图必须采自真实进程仍在运行的时刻。")
        } else {
            XCTFail("未取得进程结束前的真实首段输出，不能把完成记录当作直播截图。")
            execution.cancel()
        }
        // Always await the task before disposing of its window and temporary conversation files.
        let result = await execution.value
        XCTAssertTrue(ended)
        XCTAssertFalse(NexusLinuxRuntime.shared.isExecuting)
        XCTAssertEqual(result.callID, call.id)
        XCTAssertTrue(result.succeeded, result.output)
        XCTAssertTrue(stderr.isEmpty, stderr.joined(separator: "\n"))
        XCTAssertEqual(stdout, ["开始核对采购金额", "TOTAL=39", "核对完成"])
        XCTAssertTrue(result.output.contains("exit_code=0\nstdout:\n" + stdout.joined(separator: "\n") + "\n"), result.output)
        let actualTotal = try XCTUnwrap(stdout.first { $0.hasPrefix("TOTAL=") }?.dropFirst("TOTAL=".count))
        let total = try XCTUnwrap(Int(actualTotal))
        XCTAssertEqual(total, 39)

        vm.live.append(.result, result.output)
        vm.messages.append(ChatMessage(role: "assistant", content: "三件商品合计 \(total) 元。\n\n已用内置工具核对：12 + 18 + 9 = \(total)。", evidence: [result.output]))
        vm.live.finish(.answered, message: "已根据工具输出完成核对")
        vm.isTyping = false
        try store.save(vm.messages)
        XCTAssertEqual(try store.load().last?.evidence, [result.output])
        await attachConversationSnapshot(window, name: "会话-回答与依据")
        XCTAssertEqual(vm.live.state, .answered)
        XCTAssertEqual(modelCalls, 0)
    }

    private func attachConversationSnapshot(_ window: UIWindow, name: String) async {
        // Let SwiftUI commit its state change and the message scroll animation before drawing UIKit.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        try? await Task.sleep(for: .milliseconds(400))
        window.setNeedsLayout()
        window.layoutIfNeeded()
        window.rootViewController?.view.layoutIfNeeded()
        XCTAssertFalse(window.isHidden)
        XCTAssertGreaterThan(window.bounds.width, 0)
        XCTAssertGreaterThan(window.bounds.height, 0)
        var rendered = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered, "必须捕获已挂载窗口中的原生视图。")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
