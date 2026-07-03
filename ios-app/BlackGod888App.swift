//
//  BlackGod888App.swift
//  Black God 888 — 赵思涵私人版 · iPhone 17 Pro Max
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

class AppState: ObservableObject {
    @Published var isUnlocked = false
    @Published var currentTab: AppTab = .chat
    @Published var hapticEnabled = true
    let apiBase = "http://<SERVER_IP_ENV>:8765"

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard hapticEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

enum AppTab: Int, CaseIterable {
    case chat = 0, tools, media, monitor, me
    var title: String {
        switch self {
        case .chat: return "思涵"; case .tools: return "工具"
        case .media: return "创作"; case .monitor: return "监测"; case .me: return "我的"
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
