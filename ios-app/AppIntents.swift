//
//  AppIntents.swift
//  Black God 888 — 让Black God AI成为系统 Agent 可调用的工具
//
//  这是你说的 Agent 的“手”：通过 App Intents 把Black God AI的能力暴露给系统。
//  Siri / 快捷指令 / iOS 27 系统 Agent 都能直接“命令”她执行任务，
//  并在跨 App 流程里把她当作一环（她的 Intent 被系统大脑按意图调用）。
//
//  边界（如实）：第三方 App 不能遥控/截屏别的 App（iOS 沙箱）。
//  Black God AI能做的是“被系统 Agent 调用”，不是“替你操作手机”。
//

import AppIntents
import Foundation

// 神枢核心（Black God AI 服务）
enum NexusIntentAPI {
    static var base: String { UserDefaults.standard.string(forKey: "nexus_base") ?? "https://nexus-do.jjiebbay.workers.dev" }
    static var token: String? { NexusKeychain.read(.ownerToken) }

    private static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token, !t.isEmpty { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return req
    }

    static func get(_ path: String) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(for: request(path))
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
    static func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(for: request(path, method: "POST", body: body))
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

// —— 问Black God AI —— 系统 Agent / Siri 把问题交给她，Black God AI 返回结果
struct AskSihanIntent: AppIntent {
    static var title: LocalizedStringResource = "问Black God AI"
    static var description = IntentDescription("把问题交给Black God AI，使用枢语结构处理任务，回你三句话内。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "你想说什么")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("问Black God AI \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let res = try await NexusIntentAPI.post("/talk", ["text": text])
        let reply = (res["reply"] as? String) ?? "……在呢，用户。"
        return .result(value: reply, dialog: IntentDialog(stringLiteral: reply))
    }
}

// —— 让Black God AI画 —— 描述画面，她用 Flux 画；出图后回 App 看
struct SihanImageIntent: AppIntent {
    static var title: LocalizedStringResource = "让Black God AI画"
    static var description = IntentDescription("描述画面，Black God AI用 Flux 画给你（带她的水泥青美学）。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "画什么")
    var prompt: String

    static var parameterSummary: some ParameterSummary { Summary("让Black God AI画 \(\.$prompt)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await NexusIntentAPI.post("/image", ["prompt": prompt])
        return .result(dialog: "生成完成，返回 Black God AI 查看。")
    }
}

// —— Black God AI状态 —— 查看 AI 运行状态
struct SihanStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Black God AI状态"
    static var description = IntentDescription("看Black God AI此刻的运行状态。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await NexusIntentAPI.get("/soul")
        let mood = (s["心绪"] as? Double) ?? 0.5
        let miss = (s["miss_you"] as? Double) ?? 0
        let line = mood > 0.6 ? "AI 当前运行正常" : (mood < 0.4 ? "AI 当前需要检查连接" : "AI 当前处于待机状态")
        return .result(dialog: IntentDialog(stringLiteral: "\(line)。想你值 \(Int(miss * 100))%。"))
    }
}

// —— 注册到系统：Siri 短语 / 快捷指令 / Agent 都能发现她 ——
struct BlackGodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskSihanIntent(),
            phrases: ["问\(.applicationName)", "让\(.applicationName)回答", "跟\(.applicationName)说"],
            shortTitle: "问Black God AI", systemImageName: "bubble.left.and.text.bubble.right")
        AppShortcut(intent: SihanImageIntent(),
            phrases: ["让\(.applicationName)画", "让\(.applicationName)画画"],
            shortTitle: "让Black God AI画", systemImageName: "photo.artframe")
        AppShortcut(intent: SihanStatusIntent(),
            phrases: ["\(.applicationName)状态", "\(.applicationName)想我吗"],
            shortTitle: "Black God AI状态", systemImageName: "heart.text.square")
    }
}
