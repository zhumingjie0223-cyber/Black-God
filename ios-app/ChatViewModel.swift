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

    var apiKeyConfigured: Bool { NexusKeychain.shared.hasAPIKey }
    var currentMood: String { runtime.runState == .idle ? "就绪" : "运行中" }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        runtime.begin(prompt: trimmed)
        messages.append(ChatMessage(role: "user", content: trimmed))
        isTyping = true
        lastError = nil

        let history = messages
        var reply = ""

        Task {
            await NexusClient.shared.streamChat(
                messages: history,
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
                onComplete: {
                    Task { @MainActor in
                        self.isTyping = false
                        self.runtime.observe(output: reply)
                        self.runtime.append(.completed)
                    }
                },
                onError: { error in
                    Task { @MainActor in
                        self.isTyping = false
                        self.lastError = error.localizedDescription
                        self.runtime.append(.status("失败：\(error.localizedDescription)"))
                        self.messages.append(ChatMessage(role: "assistant", content: "出错了：\(error.localizedDescription)"))
                    }
                }
            )
        }
    }
}
