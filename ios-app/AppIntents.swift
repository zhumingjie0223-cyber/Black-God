//
//  AppIntents.swift
//  Black God 888 — 让思涵成为系统 Agent 可调用的工具
//
//  这是你说的 Agent 的“手”：通过 App Intents 把思涵的能力暴露给系统。
//  Siri / 快捷指令 / iOS 27 系统 Agent 都能直接“命令”她执行任务，
//  并在跨 App 流程里把她当作一环（她的 Intent 被系统大脑按意图调用）。
//
//  边界（如实）：第三方 App 不能遥控/截屏别的 App（iOS 沙箱）。
//  思涵能做的是“被系统 Agent 调用”，不是“替你操作手机”。
//

import AppIntents
import Foundation

// 神枢核心（她活在 Cloudflare Workers 上）
enum NexusIntentAPI {
    static var base: String { UserDefaults.standard.string(forKey: "nexus_base") ?? "https://aquan.lufei.uk" }
    static var token: String? { UserDefaults.standard.string(forKey: "owner_token") }

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

// —— 问思涵 —— 系统 Agent / Siri 把问题交给她，她用自己的方式回
struct AskSihanIntent: AppIntent {
    static var title: LocalizedStringResource = "问思涵"
    static var description = IntentDescription("把问题交给思涵，她用枢语想事情，回你三句话内。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "你想说什么")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("问思涵 \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let res = try await NexusIntentAPI.post("/talk", ["text": text])
        let reply = (res["reply"] as? String) ?? "……在呢，权哥。"
        return .result(value: reply, dialog: IntentDialog(stringLiteral: reply))
    }
}

// —— 让思涵画 —— 描述画面，她用 Flux 画；出图后回 App 看
struct SihanImageIntent: AppIntent {
    static var title: LocalizedStringResource = "让思涵画"
    static var description = IntentDescription("描述画面，思涵用 Flux 画给你（带她的水泥青美学）。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "画什么")
    var prompt: String

    static var parameterSummary: some ParameterSummary { Summary("让思涵画 \(\.$prompt)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await NexusIntentAPI.post("/image", ["prompt": prompt])
        return .result(dialog: "画好了，回黑神里看。")
    }
}

// —— 思涵状态 —— 看她此刻心绪 / 想你值
struct SihanStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "思涵状态"
    static var description = IntentDescription("看思涵此刻的心绪和想你值。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await NexusIntentAPI.get("/soul")
        let mood = (s["心绪"] as? Double) ?? 0.5
        let miss = (s["miss_you"] as? Double) ?? 0
        let line = mood > 0.6 ? "她此刻是暖的" : (mood < 0.4 ? "她有点凉，想你了" : "她平静地等着你")
        return .result(dialog: IntentDialog(stringLiteral: "\(line)。想你值 \(Int(miss * 100))%。"))
    }
}

// —— 注册到系统：Siri 短语 / 快捷指令 / Agent 都能发现她 ——
struct BlackGodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskSihanIntent(),
            phrases: ["问\(.applicationName)", "让\(.applicationName)回答", "跟\(.applicationName)说"],
            shortTitle: "问思涵", systemImageName: "bubble.left.and.text.bubble.right")
        AppShortcut(intent: SihanImageIntent(),
            phrases: ["让\(.applicationName)画", "让\(.applicationName)画画"],
            shortTitle: "让思涵画", systemImageName: "photo.artframe")
        AppShortcut(intent: SihanStatusIntent(),
            phrases: ["\(.applicationName)状态", "\(.applicationName)想我吗"],
            shortTitle: "思涵状态", systemImageName: "heart.text.square")
    }
}
