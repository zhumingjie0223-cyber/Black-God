//
//  ChatViewModel.swift
//  Black-God AI - 超强版
//

import SwiftUI
import Foundation
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var apiURL: String = "http://8.222.169.202/v1/messages"
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    init() {
        loadSettings()
    }
    
    // MARK: - 欢迎消息
    func addWelcomeMessage() {
        if messages.isEmpty {
            let welcome = Message(
                text: """
                👋 你好！我是 **Black-God AI** 全能助手。
                
                ✨ 我的能力：
                • 🔍 网页搜索 - 实时信息
                • 🎨 图片生成 - AI 作画
                • 📱 APK 下载 - 应用商城
                • 🌐 浏览器操作 - 自动化
                • 💾 数据库查询 - SQL 执行
                • 📝 记忆系统 - 跨会话
                • 💻 代码执行 - Python/Shell
                • 更多功能持续更新...
                
                💡 试试问我：
                "搜索 iPhone 16 最新消息"
                "生成一张赛博朋克风格的图片"
                "帮我找微信最新版 APK"
                """,
                isUser: false
            )
            messages.append(welcome)
        }
    }
    
    // MARK: - 发送消息
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        
        // 添加用户消息
        let userMessage = Message(text: text, isUser: true)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            messages.append(userMessage)
        }
        inputText = ""
        isLoading = true
        errorMessage = nil
        
        // 调用 API
        Task {
            do {
                let response = try await callAPI(message: text)
                await MainActor.run {
                    // 解析响应
                    if let imageURL = extractImageURL(from: response) {
                        let imageMessage = Message(text: "🎨 图片已生成", isUser: false, type: .image, imageURL: imageURL)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            messages.append(imageMessage)
                        }
                    }
                    
                    let aiMessage = Message(text: response, isUser: false)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        messages.append(aiMessage)
                    }
                    isLoading = false
                }
            } catch let error as URLError {
                await MainActor.run {
                    handleError(error)
                }
            } catch {
                await MainActor.run {
                    let errorMessage = Message(text: "❌ 请求失败: \(error.localizedDescription)\n\n点击右上角设置检查 API 地址", isUser: false)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        messages.append(errorMessage)
                    }
                    isLoading = false
                }
            }
        }
    }
    
    // MARK: - API 调用
    func callAPI(message: String) async throws -> String {
        guard let url = URL(string: apiURL) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        
        let body: [String: Any] = [
            "messages": [
                ["role": "user", "content": message]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // 发送请求（支持流式响应）
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }
        
        // 解析流式响应
        var result = ""
        for try await line in asyncBytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    result += text
                }
            }
        }
        
        return result.isEmpty ? "✅ 执行完成" : result
    }
    
    // MARK: - 错误处理
    func handleError(_ error: URLError) {
        var errorText = "❌ 连接失败\n\n"
        
        switch error.code {
        case .timedOut:
            errorText += "⏱️ 请求超时，请稍后重试"
        case .notConnectedToInternet:
            errorText += "📡 无网络连接，请检查网络"
        case .cannotFindHost, .cannotConnectToHost:
            errorText += "🔌 无法连接到服务器\n服务器地址: \(apiURL)\n\n请检查：\n• 服务器是否在线\n• API 地址是否正确\n• 网络是否通畅"
        case .badURL:
            errorText += "🔗 API 地址格式错误\n请在设置中检查"
        default:
            errorText += "错误代码: \(error.code.rawValue)\n\(error.localizedDescription)"
        }
        
        let message = Message(text: errorText, isUser: false)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            messages.append(message)
        }
        isLoading = false
    }
    
    // MARK: - 工具函数
    func extractImageURL(from text: String) -> String? {
        // 提取图片 URL（简单正则）
        let pattern = "https?://[^\\s]+\\.(png|jpg|jpeg|gif|webp)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let urlRange = Range(match.range, in: text) {
                    return String(text[urlRange])
                }
            }
        }
        return nil
    }
    
    func clearHistory() {
        withAnimation {
            messages.removeAll()
        }
        addWelcomeMessage()
    }
    
    func exportChat() {
        let text = messages.map { "\($0.isUser ? "👤 你" : "🤖 AI"): \($0.text)" }.joined(separator: "\n\n")
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    // MARK: - 设置
    func loadSettings() {
        if let savedURL = UserDefaults.standard.string(forKey: "apiURL") {
            apiURL = savedURL
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(apiURL, forKey: "apiURL")
    }
}

// MARK: - Message Model
struct Message: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp = Date()
    var type: MessageType = .text
    var imageURL: String?
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}

enum MessageType {
    case text
    case image
    case file
}
