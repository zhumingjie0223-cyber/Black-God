//
// ChatViewModel.swift — 神枢 iOS 对话协议客户端
//
// UI messages 只负责展示；规范 history、工具回合、计划/确认和审计均由 Cloudflare 神枢持久化。
// owner token 始终从 Keychain 读取，不存入 @AppStorage。

import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = [
        ChatMessage(role: "assistant", content: "神枢已就绪。云端工作台、浏览器与受控设备能力会按确认协议执行。", mood: "normal")
    ]
    @Published var isTyping = false
    @Published var currentMood = "在线 · 神枢"
    @Published private(set) var ownerTokenConfigured = NexusKeychain.read(.ownerToken)?.isEmpty == false
    @Published private(set) var lastTurnId: String?
    @Published var lastError: String?

    // 仅保存公开 Worker 地址；不保存 token、cookie 或第三方 API 密钥。
    @AppStorage("nexus_base") var nexusBase = "https://nexus-do.jjiebbay.workers.dev"

    func saveOwnerToken(_ token: String) throws {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            try NexusKeychain.delete(.ownerToken)
            ownerTokenConfigured = false
        } else {
            try NexusKeychain.write(value, for: .ownerToken)
            ownerTokenConfigured = true
        }
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: "user", content: trimmed))
        isTyping = true
        lastError = nil
        Task {
            do {
                let client = try NexusClient(base: nexusBase)
                let response = try await client.talk(trimmed)
                isTyping = false
                lastTurnId = response.turnId
                let reply = response.reply
                messages.append(ChatMessage(role: "assistant", content: reply, mood: detectMood(reply)))
            } catch {
                isTyping = false
                lastError = error.localizedDescription
                messages.append(ChatMessage(role: "assistant", content: "神枢请求未完成：\(error.localizedDescription)", mood: "error"))
            }
        }
    }

    func plan(capability: String, params: [String: Any]) async -> NexusAgentPlanResponse? {
        do {
            let client = try NexusClient(base: nexusBase)
            return try await client.plan(capability: capability, params: params)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func detectMood(_ text: String) -> String {
        if text.contains("失败") || text.contains("错误") { return "error" }
        if text.contains("完成") || text.contains("已执行") { return "professional" }
        return "normal"
    }
}
