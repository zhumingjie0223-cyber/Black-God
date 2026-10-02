//
//  BlackGodApp.swift
//  神枢 Black God — 纯客户端 AI 对话助手
//  自带 Anthropic API Key · 直连模型 · 本地存储 · 零后端
//

import SwiftUI
import UIKit

@main
struct BlackGodApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .tint(Color.bgGold)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    NexusLinuxRuntime.shared.cancelActive(reason: "应用进入后台，命令已停止")
                }
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
    /// 轻触反馈（切页、发送等）
    @Published var hapticEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticEnabled, forKey: Self.hapticKey) }
    }
    /// 任务完成震动（成功/失败提示），可单独关闭
    @Published var taskCompleteHapticEnabled: Bool {
        didSet { UserDefaults.standard.set(taskCompleteHapticEnabled, forKey: Self.taskHapticKey) }
    }

    private static let hapticKey = "blackgod.haptic.enabled"
    private static let taskHapticKey = "blackgod.haptic.taskComplete"

    init() {
        let defaults = UserDefaults.standard
        hapticEnabled = (defaults.object(forKey: Self.hapticKey) as? Bool) ?? true
        taskCompleteHapticEnabled = (defaults.object(forKey: Self.taskHapticKey) as? Bool) ?? true
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard hapticEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// 任务跑完时的通知级震动；受「任务完成震动」开关控制。
    func taskCompleteHaptic(success: Bool) {
        guard taskCompleteHapticEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(success ? .success : .error)
    }
}

// MARK: - 底部 Tab

enum AppTab: Int, CaseIterable {
    case chat = 0, media = 2, monitor = 3, me = 4

    /// 本地化 key，供 SwiftUI `Text(LocalizedStringKey)` 直接使用
    var titleKey: LocalizedStringKey {
        switch self {
        case .chat: return "tab.chat"
        case .media: return "tab.media"
        case .monitor: return "tab.monitor"
        case .me: return "tab.me"
        }
    }

    /// 已本地化的纯字符串，供无障碍标签、日志等非 SwiftUI 场景使用
    var title: String {
        switch self {
        case .chat: return L10n.tr("tab.chat")
        case .media: return L10n.tr("tab.media")
        case .monitor: return L10n.tr("tab.monitor")
        case .me: return L10n.tr("tab.me")
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message.fill"
        case .media: return "shippingbox.fill"
        case .monitor: return "waveform.path.ecg"
        case .me: return "person.fill"
        }
    }
}
