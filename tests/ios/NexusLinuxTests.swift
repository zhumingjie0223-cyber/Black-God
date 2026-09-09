import XCTest
@testable import BlackGod

@MainActor
final class NexusLinuxTests: XCTestCase {
    func testGuestDiskCapacityReportsOnlyAppBudget() async throws {
        let result = try await NexusLinuxRuntime.shared.execute(command: "stat -f -c '%S %b' .")
        XCTAssertTrue(result.succeeded, result.output)
        let values = result.output.split(whereSeparator: { $0.isWhitespace }).compactMap { Int64($0) }
        XCTAssertEqual(values.count, 2, result.output)
        if values.count == 2 { XCTAssertEqual(values[0] * values[1], NexusStorage.budget()) }
    }
    func testRealLinuxBootAndExitStatus() async throws {
        let runtime = NexusLinuxRuntime.shared
        let result = try await runtime.execute(command: "uname -m; printf 'hello\\n'; printf 'problem\\n' >&2; exit 7")
        XCTAssertTrue(result.output.contains("aarch64"), result.output)
        XCTAssertTrue(result.output.contains("hello"), result.output)
        XCTAssertTrue(result.errorOutput.contains("problem"), result.errorOutput)
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertNil(result.failure)
    }
}

@MainActor
extension NexusLinuxTests {
    func testFilesPersistWithinWorkspaceAndMultilineScriptsRun() async throws {
        let workspace = UUID()
        let runtime = NexusLinuxRuntime.shared
        let first = try await runtime.execute(command: "printf '你好\\n' > result.txt\nwc -l result.txt", workspace: workspace)
        XCTAssertTrue(first.succeeded)
        let next = try await runtime.execute(command: "cat result.txt", workspace: workspace)
        XCTAssertEqual(next.output, "你好\n")
    }
    func testTimeoutKillsChildrenAndNextCommandWorks() async throws {
        let runtime = NexusLinuxRuntime.shared
        do {
            _ = try await runtime.execute(command: "sleep 20 & wait", timeout: 0.1)
            XCTFail("必须超时")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertEqual(ISHKernel.shared.reapAndCountGuestProcesses(), 0)
        let result = try await runtime.execute(command: "printf recovered")
        XCTAssertEqual(result.output, "recovered")
    }
    func testCancellationKillsChildren() async throws {
        let runtime = NexusLinuxRuntime.shared
        let task = Task { try await runtime.execute(command: "sleep 20 & wait") }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("应取消") } catch is CancellationError {} catch { XCTFail(error.localizedDescription) }
        XCTAssertEqual(ISHKernel.shared.reapAndCountGuestProcesses(), 0)
    }
    func testLargeOutputFailsAndReadersAreReleased() async throws {
        let runtime = NexusLinuxRuntime.shared
        let result = try await runtime.execute(command: "yes x")
        XCTAssertFalse(result.succeeded)
        XCTAssertNotNil(result.failure)
        XCTAssertLessThanOrEqual(result.output.utf8.count, 262144)
        // Reader poll interval is 500ms; no command starts until its processes finish.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(runtime.diagnostics.contains("activeExecutions=0"), runtime.diagnostics)
        XCTAssertTrue(runtime.diagnostics.contains("liveReaders=0"), runtime.diagnostics)
    }
    func testRepeatedCommandsLeaveNoGuestProcesses() async throws {
        let runtime = NexusLinuxRuntime.shared
        for _ in 0..<12 {
            let result = try await runtime.execute(command: "true")
            XCTAssertTrue(result.succeeded)
        }
        XCTAssertEqual(ISHKernel.shared.reapAndCountGuestProcesses(), 0)
    }
    func testBackgroundChildDoesNotOutliveCommand() async throws {
        let runtime = NexusLinuxRuntime.shared
        _ = try await runtime.execute(command: "sleep 20 >/dev/null 2>&1 & printf done")
        XCTAssertEqual(ISHKernel.shared.reapAndCountGuestProcesses(), 0)
    }
    func testInvalidCommandIsRejected() async {
        for command in ["", "a\0b", String(repeating: "x", count: 32769)] {
            do { _ = try await NexusLinuxRuntime.shared.execute(command: command); XCTFail("应拒绝") } catch {}
        }
    }
}

@MainActor
extension NexusLinuxTests {
    func testModelToolExecutesRealLinuxAndReturnsEvidence() async throws {
        var registry = NexusToolRegistry()
        registry.register(NexusLinuxTool(workspace: UUID(), isEnabled: { true }))
        var round = 0
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            if prompt.contains("[任务规划]") { return "{\"steps\":[\"运行脚本\"]}" }
            XCTAssertTrue(prompt.contains("stdout:"))
            XCTAssertTrue(prompt.contains("42"))
            return "{\"passed\":true,\"issues\":[]}"
        }, nativeTurn: { messages, definitions in
            XCTAssertEqual(definitions.map(\.name), ["shell_execute"])
            round += 1
            if round == 1 {
                let data = Data(#"{"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"call_linux","type":"function","function":{"name":"shell_execute","arguments":"{\"command\":\"awk 'BEGIN { print 6*7 }'\"}"}}]},"finish_reason":"tool_calls"}]}"#.utf8)
                return try NexusNativeCodec.decode(data, type: .openAICompatible)
            }
            guard case .results(let results) = messages.last else { throw NexusError.invalidResponse }
            XCTAssertTrue(results[0].1.succeeded)
            XCTAssertTrue(results[0].1.output.contains("42"))
            return try NexusNativeCodec.decode(Data(#"{"choices":[{"message":{"content":"脚本运行结果：42"},"finish_reason":"stop"}]}"#.utf8), type: .openAICompatible)
        })
        let result = try await engine.run(goal: "用awk计算6乘7")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.executor?.toolTraces.count, 1)
    }
    func testDisabledToolNeverRuns() async {
        let tool = NexusLinuxTool(workspace: UUID(), isEnabled: { false })
        let result = await tool.execute(NexusToolCall(id: UUID(), name: "shell_execute", arguments: ["command": "echo unexpected"]))
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.output.contains("关闭"))
    }
    func testUTF8AcrossSeparateWrites() async throws {
        let result = try await NexusLinuxRuntime.shared.execute(command: "printf '\\344'; sleep 0.05; printf '\\275'; sleep 0.05; printf '\\240\\n'")
        XCTAssertEqual(result.output, "你\n")
    }
    func testConcurrentCommandIsRejectedWithoutKillingFirst() async throws {
        let runtime = NexusLinuxRuntime.shared
        let first = Task { try await runtime.execute(command: "sleep 0.4; printf first") }
        try await Task.sleep(for: .milliseconds(100))
        do { _ = try await runtime.execute(command: "printf second"); XCTFail("不应并发启动") }
        catch { XCTAssertTrue(error.localizedDescription.contains("另一项任务")) }
        let result = try await first.value
        XCTAssertEqual(result.output, "first")
    }
}

@MainActor
extension NexusLinuxTests {
    func testIdenticalShellCommandIsNotCachedAfterStateChanges() async throws {
        var registry = NexusToolRegistry()
        registry.register(NexusLinuxTool(workspace: UUID(), isEnabled: { true }))
        var round = 0
        var observed: [String] = []
        let engine = NexusReasoningEngine(tools: registry, model: { prompt in
            prompt.contains("[任务规划]") ? "{\"steps\":[\"重复运行\"]}" : "{\"passed\":true,\"issues\":[]}"
        }, nativeTurn: { messages, _ in
            round += 1
            if case .results(let results) = messages.last { observed.append(results[0].1.output) }
            if round <= 2 {
                let call = NexusToolCall(id: UUID(), name: "shell_execute", arguments: ["command": "n=$(cat n 2>/dev/null || echo 0); n=$((n+1)); echo \"$n\" > n; cat n"])
                return NexusNativeReply(text: "", calls: [NexusNativeCall(providerID: "repeat_\(round)", call: call)], assistant: ["role": "assistant"])
            }
            return NexusNativeReply(text: "已执行两次", calls: [], assistant: ["role": "assistant", "content": "已执行两次"])
        })
        _ = try await engine.run(goal: "连续执行两次状态更新")
        XCTAssertEqual(observed.count, 2)
        XCTAssertTrue(observed[0].contains("stdout:\n1\n"))
        XCTAssertTrue(observed[1].contains("stdout:\n2\n"))
        XCTAssertEqual(engine.executor?.toolTraces.count, 2)
    }
}

@MainActor
extension NexusLinuxTests {
    func testWorkspaceRootsPreventCrossSessionReadsAndWrites() async throws {
        let a = UUID(), b = UUID()
        let runtime = NexusLinuxRuntime.shared
        _ = try await runtime.execute(command: "printf alpha > private.txt", workspace: a)
        let probe = "test ! -e /sessions/\(a.uuidString)/workspace/private.txt && test ! -e ../../sessions/\(a.uuidString)/workspace/private.txt; printf 'status=%s' $?"
        let result = try await runtime.execute(command: probe, workspace: b)
        XCTAssertEqual(result.output, "status=0")
        let write = try await runtime.execute(command: "echo changed > /sessions/\(a.uuidString)/workspace/private.txt", workspace: b)
        XCTAssertFalse(write.succeeded)
        let original = try await runtime.execute(command: "cat private.txt", workspace: a)
        XCTAssertEqual(original.output, "alpha")
    }
    func testSymlinksStayInsideRootAndSystemMutationsFail() async throws {
        let runtime = NexusLinuxRuntime.shared
        let workspace = UUID()
        let result = try await runtime.execute(command: "ln -s /etc/os-release local; cat local; ln -s /../../../../workspace safe; printf x > safe/x; cat x; id -u", workspace: workspace)
        XCTAssertTrue(result.succeeded, result.errorOutput)
        XCTAssertTrue(result.output.contains("Alpine Linux"), result.output)
        XCTAssertTrue(result.output.contains("1000"))
        for command in ["chroot / /bin/true", "mount -t proc proc /tmp", "echo broken > /bin/busybox", "chmod 777 /bin/busybox", "chown 0 /workspace", "mknod /workspace/disk b 1 1", "kill -9 1", "touch /bin/forbidden", "truncate -s 0 /bin/busybox", "ln /workspace/x /bin/forbidden"] {
            let attempt = try await runtime.execute(command: command, workspace: workspace)
            XCTAssertFalse(attempt.succeeded, command)
            let intact = try await runtime.execute(command: "printf intact", workspace: workspace)
            XCTAssertEqual(intact.output, "intact", command)
        }
    }
    func testJournalMarksInterruptedWithoutReplayingOrStoringCommand() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("journal.json")
        let journal = NexusExecutionJournal(url: url)
        let id = try journal.begin(workspace: UUID(), command: "example-private-token")
        XCTAssertEqual(try journal.recoverInterrupted(), 1)
        XCTAssertEqual(try journal.records().first?.status, "interrupted")
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("example-private-token"))
        XCTAssertEqual(try journal.recoverInterrupted(), 0)
        try journal.finish(id, status: "failed")
    }
}

@MainActor
extension NexusLinuxTests {
    func testWorkspaceIdentityPersistsAndSeparatesSurfaces() throws {
        let suite = "blackgod.tests.workspaces." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tools = NexusWorkspaceIdentity.id(for: "tools", defaults: defaults)
        let reloaded = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(tools, NexusWorkspaceIdentity.id(for: "tools", defaults: reloaded))
        XCTAssertNotEqual(tools, NexusWorkspaceIdentity.id(for: "chat", defaults: reloaded))
    }
}

@MainActor
extension NexusLinuxTests {
    func testTextModeRunsIdenticalStatefulCommandsTwice() async throws {
        var tools = NexusToolRegistry()
        tools.register(NexusLinuxTool(workspace: UUID(), isEnabled: { true }))
        let call = "{\"name\":\"shell_execute\",\"arguments\":{\"command\":\"echo x >> count; wc -l < count\"}}"
        var replies = ["{\"steps\":[\"写入两次\"]}", call, call, "已写入两行", "{\"passed\":true,\"issues\":[]}"]
        let engine = NexusReasoningEngine(tools: tools, model: { _ in replies.removeFirst() })
        let result = try await engine.run(goal: "重复写入两行")
        XCTAssertTrue(result.reviewPassed)
        XCTAssertEqual(engine.executor?.toolTraces.count, 2)
        XCTAssertTrue(engine.executor?.toolTraces.last?.result.contains("stdout:\n2\n") == true)
    }
}

@MainActor
extension NexusLinuxTests {
    func testFailedExecutableLaunchReapsUnstartedChild() async throws {
        let runtime = NexusLinuxRuntime.shared
        try runtime.prepare()
        let pid = ISHShellExecutor.executeExecutable("/missing-test-executable", arguments: [], environment: [:], stdinData: nil, lineCallback: nil) { _ in }
        XCTAssertLessThan(pid, 0)
        XCTAssertEqual(ISHKernel.shared.reapAndCountGuestProcesses(), 0)
        let recovered = try await runtime.execute(command: "printf launch-recovered")
        XCTAssertEqual(recovered.output, "launch-recovered")
    }
}


@MainActor
extension NexusLinuxTests {
    func testNewWorkspacesShareReadOnlySystemFilesWithoutSharingUserFiles() async throws {
        let runtime = NexusLinuxRuntime.shared, first = UUID(), second = UUID()
        let a = try await runtime.execute(command: "stat -c %i /bin/busybox; printf first > own", workspace: first)
        let b = try await runtime.execute(command: "stat -c %i /bin/busybox; test ! -e own", workspace: second)
        XCTAssertTrue(a.succeeded); XCTAssertTrue(b.succeeded)
        XCTAssertEqual(a.output, b.output)
        let mutate = try await runtime.execute(command: "printf hacked > /bin/busybox", workspace: first)
        XCTAssertFalse(mutate.succeeded)
        let unaffected = try await runtime.execute(command: "echo intact", workspace: second)
        XCTAssertEqual(unaffected.output, "intact\n")
    }
}
