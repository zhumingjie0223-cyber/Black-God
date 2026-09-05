// ChatViewModel.swift — 直连 Anthropic API，无后端

import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = [
        ChatMessage(role: "assistant", content: "神枢已就绪。请在设置中填写 API Key 开始对话。")
    ]
    @Published var isTyping = false
    @Published var lastError: String?
    @Published private(set) var runtime = NexusRuntime()
    private let agentLoop = NexusAgentLoop()
    private let verifier = NexusIndependentVerifier()
    private var handledToolCalls = Set<UUID>()
    @Published var memory = NexusMemoryStore()
    @Published var evaluations = NexusEvaluationStore()
    @Published var modelRegistry = NexusModelRegistry()

    var apiKeyConfigured: Bool { NexusKeychain.shared.hasAPIKey }
    var currentMood: String { runtime.runState == .idle ? "就绪" : "运行中" }

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

        let history = messages
        let startedAt = Date()
        var reply = ""

        Task {
            await NexusClient.shared.streamChat(
                messages: history,
                model: self.modelRegistry.selected.modelID,
                onDelta: { delta in
                    Task { @MainActor in
                        if reply.isEmpty {
                            self.messages.append(ChatMessage(role: "assistant", content: delta))
                        } else {
                            self.messages[self.messages.count - 1].content += delta
                        }
                        reply += delta
                        self.runtime.append(.text(delta))

                    }
                },
                onToolCall: { call in
                    Task { @MainActor in
                        guard !self.handledToolCalls.contains(call.id) else { return }
                        self.handledToolCalls.insert(call.id)
                        await self.runtime.execute(call)
                    }
                },
                onComplete: {
                    Task { @MainActor in
                        let calls = self.agentLoop.calls(in: reply).filter { !self.handledToolCalls.contains($0.id) }
                        for call in calls {
                            self.handledToolCalls.insert(call.id)
                            await self.runtime.execute(call)
                        }
                        self.isTyping = false
                        self.runtime.observe(output: reply)
                        let report = self.verifier.verify(goal: trimmed, output: reply)
                        self.evaluations.record(task: trimmed, success: report.passed, recovered: false, verified: report.passed, latency: Date().timeIntervalSince(startedAt))
                        self.memory.remember(reply, kind: "result", source: "assistant", confidence: 0.6)
                        self.runtime.append(.completed)
                    }
                },
                onError: { error in
                    Task { @MainActor in
                        self.isTyping = false
                        self.lastError = error.localizedDescription
                        self.evaluations.record(task: trimmed, success: false, recovered: false, verified: false, latency: Date().timeIntervalSince(startedAt))
                        self.runtime.append(.status("失败：\(error.localizedDescription)"))
                        self.messages.append(ChatMessage(role: "assistant", content: "出错了：\(error.localizedDescription)"))
                    }
                }
            )
        }
    }
}
