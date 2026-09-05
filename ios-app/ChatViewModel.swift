// ChatViewModel.swift — 直连 Anthropic API，无后端；send() 走 NexusExecutor 计划→分步执行→逐步验证→汇总

import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = [
        ChatMessage(role: "assistant", content: "神枢已就绪。请在设置中填写 API Key 开始对话。")
    ]
    @Published var isTyping = false
    @Published var lastError: String?
    @Published var statusHint: String?
    @Published private(set) var runtime = NexusRuntime()
    private let agentLoop = NexusAgentLoop()
    private let verifier = NexusIndependentVerifier()
    private var handledToolCalls = Set<UUID>()
    private var activeExecutor: NexusExecutor?
    private var activeTask: Task<Void, Never>?
    @Published var memory = NexusMemoryStore()
    @Published var evaluations = NexusEvaluationStore()
    @Published var modelRegistry = NexusModelRegistry()

    var apiKeyConfigured: Bool { NexusKeychain.shared.hasAPIKey }
    var currentMood: String { runtime.runState == .idle ? "就绪" : "运行中" }
    var currentPlan: NexusTaskPlan? { activeExecutor?.plan ?? runtime.currentPlan }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        runtime.begin(prompt: trimmed)
        let memories = memory.search(trimmed).map { "- \($0.text)" }.joined(separator: "\n")
        if !memories.isEmpty { messages.append(ChatMessage(role: "user", content: "[relevant_memory]\n\(memories)")) }
        memory.remember(trimmed, kind: "episodic", source: "user", confidence: 0.7)
        messages.append(ChatMessage(role: "user", content: trimmed))
        isTyping = true
        lastError = nil
        statusHint = "正在规划任务…"

        let selectedModel = NexusKeychain.shared.selectedModel
        let memoryContext = memories
        let startedAt = Date()

        let executor = NexusExecutor(
            planner: BasicNexusPlanner(),
            verifier: BasicNexusVerifier(),
            model: { prompt in
                var enriched: [ChatMessage] = []
                if !memoryContext.isEmpty {
                    enriched.append(ChatMessage(role: "user", content: "[relevant_memory]\n\(memoryContext)"))
                }
                enriched.append(ChatMessage(role: "user", content: prompt))
                return try await NexusModelBridge.complete(messages: enriched, model: selectedModel)
            },
            onEvent: { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    self.statusHint = event
                    self.runtime.append(.status(event))
                    if event.hasPrefix("步骤通过") || event.hasPrefix("步骤失败") {
                        self.runtime.append(.text("· \(event)\n"))
                    }
                }
            }
        )
        activeExecutor = executor

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            let final = await executor.run(goal: trimmed)
            guard !Task.isCancelled else {
                self.isTyping = false
                self.statusHint = nil
                self.runtime.append(.status("任务已取消"))
                return
            }

            if let plan = executor.plan {
                let passed = plan.steps.filter { $0.status == .passed }.count
                let failed = plan.steps.filter { $0.status == .failed }.count
                self.runtime.append(.status("步骤汇总：通过 \(passed) / 失败 \(failed) / 共 \(plan.steps.count)"))
            }

            let reply = final.trimmingCharacters(in: .whitespacesAndNewlines)
            if reply.isEmpty {
                let failureReasons = executor.verdicts.filter { !$0.passed }.map(\.reason)
                let message = failureReasons.last ?? "模型未返回任何内容"
                self.isTyping = false
                self.statusHint = nil
                self.lastError = message
                self.evaluations.record(task: trimmed, success: false, recovered: false, verified: false, latency: Date().timeIntervalSince(startedAt))
                self.runtime.append(.status("失败：\(message)"))
                self.messages.append(ChatMessage(role: "assistant", content: "出错了：\(message)"))
                return
            }

            self.messages.append(ChatMessage(role: "assistant", content: reply))
            self.runtime.append(.text(reply))

            let calls = self.agentLoop.calls(in: reply).filter { !self.handledToolCalls.contains($0.id) }
            for call in calls {
                self.handledToolCalls.insert(call.id)
                await self.runtime.execute(call)
            }

            self.isTyping = false
            self.statusHint = nil
            self.runtime.observe(output: reply)

            let report = self.verifier.verify(goal: trimmed, output: reply)
            let recovered = executor.verdicts.contains { !$0.passed } && report.passed
            self.evaluations.record(task: trimmed, success: report.passed, recovered: recovered, verified: report.passed, latency: Date().timeIntervalSince(startedAt))
            self.runtime.append(.status(report.reason))
            self.memory.remember(reply, kind: "result", source: "assistant", confidence: report.passed ? 0.7 : 0.4)
            if !report.passed {
                self.lastError = report.reason
            }
            self.runtime.append(.completed)
            self.activeExecutor = nil
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        activeExecutor = nil
        isTyping = false
        statusHint = nil
        runtime.cancel()
    }

    init() {
        NotificationCenter.default.addObserver(forName: .nexusDataWiped, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resetAfterWipe() }
        }
    }

    /// 「清除全部数据」之后把会话恢复到首次启动状态（记忆/评估存储各自监听同一通知清空）
    func resetAfterWipe() {
        cancel()
        handledToolCalls.removeAll()
        lastError = nil
        messages = [ChatMessage(role: "assistant", content: "神枢已就绪。请在设置中填写 API Key 开始对话。")]
    }
}
