import Foundation

/// Black God AI 的任务运行时：协调意图、模型、工具和实时事件。
@MainActor
final class NexusRuntime: ObservableObject {
    @Published private(set) var runState: NexusRunState = .idle
    @Published private(set) var events: [NexusRunEvent] = []
    @Published private(set) var metrics = NexusRunMetrics()
    @Published private(set) var currentPlan: NexusTaskPlan?
    private(set) var observations: [NexusObservation] = []
    private(set) var verdicts: [NexusVerdict] = []

    private let planner: NexusPlanning = BasicNexusPlanner()
    private let verifier: NexusVerifying = BasicNexusVerifier()
    private var executionLoop = NexusExecutionLoop()
    private var activeTask: Task<Void, Never>?
    private let recovery = NexusRecoveryController()
    private let autonomy = NexusAutonomyController()
    private let permissionGate = NexusPermissionGate.standard
    private let approvalQueue = NexusApprovalQueue()
    private let checkpointStore = NexusCheckpointStore()
    private(set) var sessionID = UUID()

    func begin(prompt: String) {
        var loop = executionLoop
        loop.installDefaults()
        executionLoop = loop
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        runState = .planning
        currentPlan = planner.makePlan(for: text)
        observations.removeAll()
        verdicts.removeAll()
        append(.planned(prompt: text))
        append(.status("计划已生成：\(currentPlan?.steps.count ?? 0) 步"))
    }

    func append(_ event: NexusRunEvent) {
        events.append(event)
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    func execute(_ call: NexusToolCall) async {
        guard autonomy.shouldExecute(call) else {
            append(.status("已跳过重复工具调用"))
            return
        }
        let approved = approvalQueue.decision(for: call.id) ?? false
        guard case .success = permissionGate.authorize(call, approved: approved) else {
            approvalQueue.enqueue(call)
            runState = .waitingForInput
            append(.status("工具调用等待批准：\(call.name)"))
            return
        }
        runState = .runningTool(name: call.name)
        metrics.toolCalls += 1
        append(.toolStarted(name: call.name, input: call.arguments.description))
        var loop = executionLoop
        var result = await loop.run(call)
        executionLoop = loop
        if !result.succeeded, recovery.nextAttempt(for: call.id) != nil {
            append(.status("工具失败，正在重试"))
            result = await loop.run(call)
        }
        append(.toolOutput(result.output))
        autonomy.record(call, succeeded: result.succeeded)
        if result.succeeded { metrics.successfulToolCalls += 1 } else { metrics.failedToolCalls += 1 }
        observe(output: result.output)
        if !result.succeeded && autonomy.canReplan() {
            runState = .planning
            metrics.replans += 1
            append(.status("验证失败，允许重新规划"))
        } else {
            runState = result.succeeded ? .streaming : .failed(result.output)
        }
    }

    func observe(output: String) {
        guard let step = currentPlan?.steps.first(where: { $0.status == .running || $0.status == .pending }) else { return }
        observations.append(NexusObservation(stepID: step.id, output: output, timestamp: Date()))
        let verdict = verifier.verify(goal: currentPlan?.goal ?? "", output: output)
        verdicts.append(verdict)
        if let plan = currentPlan {
            checkpointStore.save(NexusCheckpoint(plan: plan, observations: observations, verdicts: verdicts, savedAt: Date()))
        }
        append(.status(verdict.passed ? "结果验证通过" : "结果验证失败：\(verdict.reason)"))
    }

    func approveAndExecute(_ call: NexusToolCall) async {
        approvalQueue.approve(call.id)
        await execute(call)
    }

    func reject(_ call: NexusToolCall) {
        approvalQueue.reject(call.id)
        runState = .failed("用户拒绝工具调用：\(call.name)")
        append(.status("已拒绝：\(call.name)"))
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        runState = .cancelled
        append(.status("任务已取消"))
    }

    func restoreCheckpoint() {
        guard let checkpoint = checkpointStore.load() else { return }
        currentPlan = checkpoint.plan
        observations = checkpoint.observations
        verdicts = checkpoint.verdicts
        runState = .paused
        append(.status("已恢复任务检查点"))
    }

    func reset() {
        sessionID = UUID()
        events.removeAll()
        currentPlan = nil
        observations.removeAll()
        verdicts.removeAll()
        runState = .idle
    }
}

enum NexusRunState: Equatable {
    case idle, planning, waitingForInput, runningTool(name: String), streaming, paused, completed, failed(String), cancelled
}

enum NexusRunEvent: Identifiable {
    case planned(prompt: String)
    case status(String)
    case text(String)
    case toolStarted(name: String, input: String)
    case toolOutput(String)
    case artifact(name: String, path: String)
    case usage(input: Int, output: Int)
    case completed

    var id: UUID { UUID() }
}

/// 枢语只暴露协议边界；具体词库和引擎可独立替换，不污染 UI。
struct ShuyuIntent {
    let operation: String
    let target: String
    let metadata: [String: String]
}

protocol ShuyuIntentParsing {
    func parse(_ text: String) -> ShuyuIntent
}

struct BasicShuyuParser: ShuyuIntentParsing {
    func parse(_ text: String) -> ShuyuIntent {
        ShuyuIntent(operation: "understand", target: text, metadata: ["protocol": "shuyu"])
    }
}
