import Foundation

// Compile the production executor, parser and bridge with this deterministic
// network boundary. No API keys, network access or simulator are needed.
struct ChatMessage { let role: String; let content: String }
enum NexusError: Error { case invalidResponse }
enum FixtureError: Error { case network }

final class StreamProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var cancellations = 0
    var snapshot: (starts: Int, cancellations: Int) {
        lock.lock(); defer { lock.unlock() }
        return (starts, cancellations)
    }
    func reset() { lock.lock(); defer { lock.unlock() }; starts = 0; cancellations = 0 }
    func start() { lock.lock(); defer { lock.unlock() }; starts += 1 }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancellations += 1 }
}

actor NexusClient {
    enum Mode { case normal, duplicateCallbacks, noCallback, empty, error, waiting, completionOnCancel }
    static let shared = NexusClient()
    nonisolated let probe = StreamProbe()
    private var mode = Mode.normal
    func configure(_ mode: Mode) { self.mode = mode; probe.reset() }

    func streamChat(
        messages: [ChatMessage], model: String? = nil,
        onDelta: @escaping (String) -> Void,
        onToolCall: @escaping (NexusToolCall) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        let mode = self.mode
        probe.start()
        switch mode {
        case .normal:
            onDelta("hello "); onDelta("world"); onComplete()
        case .duplicateCallbacks:
            onDelta("answer"); onComplete(); onDelta(" ignored")
            onError(FixtureError.network); onComplete()
        case .noCallback:
            onDelta("fallback")
        case .empty:
            onComplete()
        case .error:
            onDelta("partial"); onError(FixtureError.network); onComplete()
        case .waiting, .completionOnCancel:
            onDelta("partial")
            await withTaskCancellationHandler {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { onError(error) }
            } onCancel: {
                self.probe.cancel()
                // Exercise the race where cancelling transport synchronously
                // invokes its successful-completion callback with partial text.
                if mode == .completionOnCancel { onComplete() }
            }
        }
    }
}

private struct SingleStepPlanner: NexusPlanning {
    func makePlan(for goal: String) -> NexusTaskPlan {
        NexusTaskPlan(id: UUID(), goal: goal, steps: [NexusTaskStep(title: "计算")], createdAt: Date())
    }
}

@main
@MainActor
struct RuntimeRegressionTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAILED: \(message)") }
    }

    static func main() async throws {
        testArithmetic()
        testParser()
        await testExecutor()
        try await testBridge()
        testAgentPlanningAndVerification()
        try await testAdvancedExecutor()
        print("PASS: \(checks) runtime regression checks (arithmetic, parsing, planning, budgets, checkpoint recovery, cancellation).")
    }

    static func testArithmetic() {
        for (input, value) in [
            ("(3+4)*2", 14.0), ("8/4/2", 1), ("1-2-3", -4),
            ("-(-3)+.5", 3.5), ("2*-3", -6), ("1. + 0.25", 1.25),
            (" \t3\n + 4 ", 7), ("-(2+3)*4", -20)
        ] { expect(NexusArithmetic.evaluate(input) == value, "arithmetic \(input)") }

        for input in ["", " ", ".", "1+", "((2)", "2(3)", "1..2", "1 2", "2**3", "3/0", "0/0", "abc", "2^3",
                      String(repeating: "9", count: 400),
                      String(repeating: "9", count: 200) + "*" + String(repeating: "9", count: 200),
                      String(repeating: "-", count: 100) + "1",
                      String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100),
                      String(repeating: "1+", count: 3000) + "1"] {
            expect(NexusArithmetic.evaluate(input) == nil, "reject malformed, overflowing or unbounded arithmetic")
        }

        // Deterministic fuzz coverage: malformed input must never crash or emit
        // NaN/infinity. A fixed PRNG keeps a failing case reproducible.
        var seed: UInt64 = 0x12345678
        let alphabet = Array("0123456789.+-*/() x")
        for _ in 0..<1000 {
            var input = ""
            for _ in 0..<40 {
                seed = seed &* 6364136223846793005 &+ 1
                input.append(alphabet[Int(seed >> 32) % alphabet.count])
            }
            let value = NexusArithmetic.evaluate(input)
            expect(value == nil || value!.isFinite, "fuzz arithmetic stays finite")
        }
    }

    static func testParser() {
        let object = #"{"name":"calc","arguments":{"expr":"(3+4)*2"}}"#
        expect(NexusToolCallParser.parse(object).first?.arguments["expr"] == "(3+4)*2", "raw call parses")
        expect(NexusToolCallParser.stripCalls(from: object).isEmpty, "raw call is hidden")
        let multiline = "[\n  \(object),\n  \(object)\n]"
        expect(NexusToolCallParser.parse(multiline).count == 2, "multiline array parses")
        expect(NexusToolCallParser.stripCalls(from: multiline).isEmpty, "multiline array is hidden")
        let fenced = "before\n```json\n\(object)\n```\nafter"
        expect(NexusToolCallParser.parse(fenced).count == 1, "fenced call parses")
        expect(NexusToolCallParser.stripCalls(from: fenced) == "before\nafter", "only call fence removed")
        let plainJSON = "```json\n{\"name\":\"example\",\"value\":42}\n```"
        expect(NexusToolCallParser.parse(plainJSON).isEmpty, "ordinary JSON is not a call")
        expect(NexusToolCallParser.stripCalls(from: plainJSON) == plainJSON, "ordinary JSON survives")
        let mixed = "```json\n{\"name\":\"echo\",\"arguments\":{\"text\":\"first\"}}\n```\n```tool\n\(object)\n```"
        expect(NexusToolCallParser.parse(mixed).map(\.name) == ["echo", "calc"], "mixed fences retain execution order")
        let scalars = NexusToolCallParser.parse(#"{"name":"echo","arguments":{"one":1,"zero":0,"flag":true}}"#)[0]
        expect(scalars.arguments["one"] == "1" && scalars.arguments["zero"] == "0", "numbers stay numbers")
        expect(scalars.arguments["flag"] == "true", "booleans stay booleans")
        let incomplete = "```tool\n\(object)"
        expect(NexusToolCallParser.parse(incomplete).isEmpty, "incomplete fence does not execute")
        expect(NexusToolCallParser.stripCalls(from: incomplete) == incomplete, "incomplete fence survives")
        let mixedArray = "[\(object),{\"value\":42}]"
        expect(NexusToolCallParser.parse(mixedArray).isEmpty, "mixed array does not partially execute")
        expect(NexusToolCallParser.stripCalls(from: mixedArray) == mixedArray, "mixed array survives")
    }

    static func testExecutor() async {
        var prompts: [String] = []
        let executor = NexusExecutor(planner: SingleStepPlanner(), model: { prompt in
            prompts.append(prompt)
            return prompts.count == 1
                ? "```tool\n{\"name\":\"calc\",\"arguments\":{\"expr\":\"(3+4)*2\"}}\n```"
                : "14"
        })
        let output = await executor.run(goal: "14")
        expect(output.contains("14") && !output.contains("```"), "executor returns final answer")
        expect(executor.toolTraces.count == 1 && executor.toolTraces[0].result == "14", "calculator executes once")
        expect(prompts.count == 2 && prompts[1].contains("=> 14"), "tool result fed back to model")

        let finalOnly = NexusExecutor(planner: SingleStepPlanner(), model: { _ in
            "{\"name\":\"calc\",\"arguments\":{\"expr\":\"2+2\"}}"
        }, maxToolRounds: 1)
        let blockedOutput = await finalOnly.run(goal: "4")
        expect(blockedOutput.isEmpty && finalOnly.toolTraces.isEmpty, "round cap never exposes or executes raw calls")
        let invalid = await NexusCalculatorTool().execute(NexusToolCall(name: "calc", arguments: ["expr": "1+"]))
        expect(!invalid.succeeded, "invalid math becomes failed tool result")
        let unknown = await NexusToolRegistry().execute(NexusToolCall(name: "missing"))
        expect(!unknown.succeeded, "unknown tool returns failure")
    }

    static func testBridge() async throws {
        for (mode, answer) in [(NexusClient.Mode.normal, "hello world"), (.duplicateCallbacks, "answer"), (.noCallback, "fallback")] {
            await NexusClient.shared.configure(mode)
            let output = try await NexusModelBridge.complete("test")
            expect(output == answer, "bridge assembles and completes exactly once")
        }
        await NexusClient.shared.configure(.empty)
        do {
            _ = try await NexusModelBridge.complete("test")
            expect(false, "empty response must fail")
        } catch NexusError.invalidResponse { expect(true, "empty response rejected") }

        await NexusClient.shared.configure(.error)
        do {
            _ = try await NexusModelBridge.complete("test")
            expect(false, "transport error must fail")
        } catch FixtureError.network { expect(true, "transport error preserved") }

        await NexusClient.shared.configure(.normal)
        let beforeStart = Task { try await NexusModelBridge.complete("test") }
        beforeStart.cancel()
        do {
            _ = try await beforeStart.value
            expect(false, "pre-start cancellation must fail")
        } catch is CancellationError { expect(true, "pre-start cancellation preserved") }
        expect(NexusClient.shared.probe.snapshot.starts == 0, "cancel before start makes no network request")

        for mode in [NexusClient.Mode.waiting, .completionOnCancel] {
            await NexusClient.shared.configure(mode)
            let running = Task { try await NexusModelBridge.complete("test") }
            for _ in 0..<1000 {
                if NexusClient.shared.probe.snapshot.starts > 0 { break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            expect(NexusClient.shared.probe.snapshot.starts == 1, "stream started")
            running.cancel()
            do {
                _ = try await running.value
                expect(false, "in-flight cancellation must fail even when completion races")
            } catch is CancellationError { expect(true, "in-flight cancellation preserved") }
            expect(NexusClient.shared.probe.snapshot.cancellations == 1, "network task actually cancelled")
        }
    }
}
