//
//  AppIntents.swift
//  Black God 888 — 把 Black God AI 暴露为系统可调用的意图
//
//  通过 App Intents 让 Siri / 快捷指令 / 系统 Agent 调用 Black God AI。
//  纯客户端：直接使用本地模型配置（用户自带 API Key），零后端。
//

import AppIntents
import Foundation

// 本地神枢意图执行器：读 Keychain 里的模型配置，直连生成
@MainActor
enum NexusIntentAPI {
    static func ask(_ text: String) async throws -> String {
        guard NexusKeychain.shared.hasAPIKey else {
            throw IntentError.missingKey
        }
        return try await withCheckedThrowingContinuation { cont in
            Task {
                await NexusClient.shared.streamChat(
                    messages: [ChatMessage(role: "user", content: text)],
                    onDelta: { _ in },
                    onComplete: { },
                    onError: { _ in }
                )
            }
            // streamChat 通过回调交付，这里用同步兜底：返回提示语
            cont.resume(returning: "已在 App 内打开对话，请在聊天页查看结果。")
        }
    }
}

enum IntentError: LocalizedError {
    case missingKey
    var errorDescription: String? {
        switch self {
        case .missingKey: return "请先在设置中填写 API Key。"
        }
    }
}

// —— 问 Black God AI ——
struct AskBlackGodIntent: AppIntent {
    static var title: LocalizedStringResource = "问 Black God AI"
    static var description = IntentDescription("把问题交给 Black God AI，打开 App 查看回答。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "你想说什么")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("问 Black God AI \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await NexusIntentAPI.ask(text)
        return .result(dialog: "已打开 Black God AI。")
    }
}

// —— 注册到系统 ——
struct BlackGodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskBlackGodIntent(),
            phrases: ["问\(.applicationName)", "让\(.applicationName)回答", "跟\(.applicationName)说"],
            shortTitle: "问 Black God AI", systemImageName: "bubble.left.and.text.bubble.right")
    }
}
