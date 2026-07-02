//
//  RootView.swift — 根视图 + TabBar
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient.darkGradient.ignoresSafeArea()
            Group {
                switch appState.currentTab {
                case .chat: ChatView()
                case .tools: ToolsView()
                case .media: MediaView()
                case .monitor: MonitorView()
                case .me: MeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            CustomTabBar()
        }
        .ignoresSafeArea(.keyboard)
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
                        Text(tab.title).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(appState.currentTab == tab ? AnyShapeStyle(LinearGradient.goldGradient) : AnyShapeStyle(Color.bgTextSecondary))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 12).padding(.bottom, 28)
        .background(Color.bgCard.overlay(Rectangle().fill(Color.bgGold.opacity(0.1)).frame(height: 0.5), alignment: .top).ignoresSafeArea(edges: .bottom))
    }
}
