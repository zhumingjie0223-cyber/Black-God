//
//  RootView.swift — 根视图 + TabBar
//

import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var appState: AppState
    @StateObject private var chatModel = ChatViewModel()
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient.darkGradient.ignoresSafeArea()
            Group {
                switch appState.currentTab {
                case .chat: ChatView(vm: chatModel)
                case .tools: ToolsView(chat: chatModel)
                case .media: MediaView()
                case .monitor: MonitorView()
                case .me: MeView(cognitive: chatModel.cognitive, memory: chatModel.memory, skills: chatModel.skills, practice: chatModel.practice)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { CustomTabBar() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                if scenePhase == .active, appState.currentTab == .chat, !chatModel.isTyping,
                   !NexusLinuxRuntime.shared.isExecuting, chatModel.practice.due {
                    chatModel.practice.start()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { chatModel.practice.stop() } }
        .onChange(of: appState.currentTab) { _, tab in if tab != .chat { chatModel.practice.stop() } }
    }
}

struct CustomTabBar: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    appState.haptic(.light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { appState.currentTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 22, weight: .medium))
                            .symbolEffect(.bounce, value: appState.currentTab == tab)
                        Text(tab.titleKey).font(.system(size: 10, weight: .medium))
                    }
                    .accessibilityLabel(tab.title)
                    .foregroundStyle(appState.currentTab == tab ? AnyShapeStyle(LinearGradient.goldGradient) : AnyShapeStyle(Color.bgTextSecondary))
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(.top, 12).padding(.bottom, 28)
        .background(Color.bgCard.overlay(Rectangle().fill(Color.bgGold.opacity(0.1)).frame(height: 0.5), alignment: .top).ignoresSafeArea(edges: .bottom))
    }
}
