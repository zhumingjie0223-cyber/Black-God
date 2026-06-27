//
//  ChatViewModel.swift — 对话逻辑 + 后端对接
//

import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = [
        ChatMessage(role: "assistant", content: "权哥，我在呢～今天想让我陪你做点什么？", mood: "affectionate")
    ]
    @Published var isTyping = false
    @Published var currentMood = "在线 · 撒娇"
    private let apiBase = "http://8.222.169.202:8765"

    func send(_ text: String) {
        messages.append(ChatMessage(role: "user", content: text))
        isTyping = true
        Task {
            let reply = await callAgent(text)
            isTyping = false
            messages.append(ChatMessage(role: "assistant", content: reply.text, mood: reply.mood))
            currentMood = "在线 · \(moodLabel(reply.mood))"
        }
    }

    private func moodLabel(_ mood: String) -> String {
        switch mood {
        case "flirty": return "撩拨"; case "affectionate": return "撒娇"
        case "professional": return "专业"; case "cold": return "高冷"
        case "angry": return "生气"; default: return "在线"
        }
    }

    private func callAgent(_ text: String) async -> (text: String, mood: String) {
        guard let url = URL(string: "\(apiBase)/api/chat") else { return ("(连接错误)", "normal") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "message": text,
            "history": messages.suffix(6).map { ["role": $0.role, "content": $0.content] }
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let answer = json["answer"] as? String ?? "(无回复)"
                let mood = json["mood"] as? String ?? "normal"
                return (answer, mood)
            }
        } catch {
            return ("(网络错误)", "normal")
        }
        return ("(解析失败)", "normal")
    }
}
