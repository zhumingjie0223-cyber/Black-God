//
//  AppIntents.swift
//  Black God — 把 Black God AI 暴露为系统可调用的意图
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
        let model = NexusKeychain.shared.selectedModel
        guard !(NexusKeychain.shared.key(for: NexusModelCatalog.entry(for: model).credentialID) ?? "").isEmpty else {
            throw IntentError.missingKey
        }
        let connection = NexusModelCatalog.entry(for: model)
        let key = NexusKeychain.shared.key(for: connection.credentialID)
        let client = NexusClient(keyProvider: { _ in key }, resolver: { _ in connection })
        var tools = NexusToolRegistry(control: .shared)
        tools.register(NexusCausalTool()); tools.register(NexusDependencyTool())
        tools.register(NexusShuyuTool())
        tools.register(NexusClockTool())
        tools.register(NexusCalculatorTool())
        if NexusLinuxTool.enabled { tools.register(NexusLinuxTool(workspace: NexusWorkspaceIdentity.id(for: "shortcuts"))) }
        let nativeTurn: NexusNativeTurn? = NexusModelCatalog.entry(for: model).usesNativeTools ? {
            try await client.nativeTurn(messages: $0, tools: $1, model: model)
        } : nil
        tools.register(NexusShuyuRunTool(tools: tools))
        let engine = NexusReasoningEngine(tools: tools, model: { try await client.complete(messages: [ChatMessage(role: "user", content: $0)], model: model) },
            nativeTurn: nativeTurn)
        let result = try await engine.run(goal: text)
        return result.text + (result.warning.map { "\n\n" + $0 } ?? "")
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
    static var description = IntentDescription("把问题交给 Black God AI，返回实际回答。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "你想说什么")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("问 Black God AI \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = try await NexusIntentAPI.ask(text)
        return .result(dialog: "\(answer)")
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
