import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        ZStack {
            LinearGradient.darkGradient.ignoresSafeArea()
            Group {
                switch appState.currentTab {
                case .chat: ChatView()
                case .tools: ToolsView()
                case .monitor: MonitorView()
                case .me: MeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { CustomTabBar() }
    }
}

struct CustomTabBar: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    appState.haptic(.light)
                    appState.currentTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 20, weight: .medium))
                        Text(tab.titleKey).font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(appState.currentTab == tab ? Color.bgGoldLight : Color.bgTextSecondary)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(appState.currentTab == tab ? .isSelected : [])
            }
        }
        .background(Color.bgCard.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Color.bgGold.opacity(0.15).frame(height: 0.5) }
    }
}
