import AppIntents
import Foundation

// 本地神枢意图执行器：与聊天共用任务服务（记忆、技能、检查点、工具边界）。
@MainActor
enum NexusIntentAPI {
    static func ask(_ text: String) async throws -> String {
        try await NexusTaskService.ask(text, source: "shortcuts")
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

struct AskBlackGodIntent: AppIntent {
    static var title: LocalizedStringResource = "问 Black God AI"
    static var description = IntentDescription("把问题交给 Black God AI，返回实际回答；与聊天共用记忆、技能与任务检查点边界。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "你想说什么")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("问 Black God AI \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let answer = try await NexusIntentAPI.ask(text)
            return .result(dialog: "\(answer)")
        } catch NexusTaskServiceError.missingKey {
            throw IntentError.missingKey
        }
    }
}

struct BlackGodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskBlackGodIntent(),
            phrases: ["问\(.applicationName)", "让\(.applicationName)回答", "跟\(.applicationName)说"],
            shortTitle: "问 Black God AI", systemImageName: "bubble.left.and.text.bubble.right")
    }
}
