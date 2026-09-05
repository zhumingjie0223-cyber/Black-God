//
//  BlackGod888App.swift
//  神枢 Black God — 纯客户端 AI 对话助手
//  自带 Anthropic API Key · 直连模型 · 本地存储 · 零后端
//

import SwiftUI

@main
struct BlackGod888App: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .tint(Color.bgGold)
        }
    }
}

// MARK: - 多语言

/// 本地化字符串统一入口。
/// 词条定义在 `zh-Hans.lproj/Localizable.strings`（简体中文，开发语言）
/// 与 `en.lproj/Localizable.strings`（英文），跟随系统语言自动切换。
///
/// 用法：
///   `L10n.tr("tab.chat")`                 → 普通词条
///   `L10n.tr("error.network", "超时")`   → 带格式参数的词条
///   SwiftUI 里 `Text("tab.chat")` 会自动按 key 查表，无需经过 L10n。
enum L10n {
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        return args.isEmpty ? format : String(format: format, locale: Locale.current, arguments: args)
    }

    /// 当前是否为中文界面（用于少数需要按语言分支的排版逻辑）
    static var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }
}

// MARK: - 全局状态

class AppState: ObservableObject {
    @Published var isUnlocked = false
    @Published var currentTab: AppTab = .chat
    @Published var hapticEnabled = true

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard hapticEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - 底部 Tab

enum AppTab: Int, CaseIterable {
    case chat = 0, tools, media, monitor, me

    /// 本地化 key，供 SwiftUI `Text(LocalizedStringKey)` 直接使用
    var titleKey: LocalizedStringKey {
        switch self {
        case .chat: return "tab.chat"
        case .tools: return "tab.tools"
        case .media: return "tab.media"
        case .monitor: return "tab.monitor"
        case .me: return "tab.me"
        }
    }

    /// 已本地化的纯字符串，供无障碍标签、日志等非 SwiftUI 场景使用
    var title: String {
        switch self {
        case .chat: return L10n.tr("tab.chat")
        case .tools: return L10n.tr("tab.tools")
        case .media: return L10n.tr("tab.media")
        case .monitor: return L10n.tr("tab.monitor")
        case .me: return L10n.tr("tab.me")
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message.fill"; case .tools: return "terminal.fill"
        case .media: return "wand.and.stars"; case .monitor: return "waveform.path.ecg"
        case .me: return "person.fill"
        }
    }
}
