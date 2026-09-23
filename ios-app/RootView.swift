//
//  RootView.swift — 根视图 + TabBar
//

import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject var appState: AppState
    @AppStorage("blackgod.linux.modelTools") private var allowExecution = true
    @State private var keyboardVisible = false
    @StateObject private var chatModel = ChatViewModel()
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient.darkGradient.ignoresSafeArea()
            HStack(spacing: 0) {
                if sizeClass == .regular { BGSidebar() }
                Group {
                switch appState.currentTab {
                case .chat: ChatView(vm: chatModel)
                case .media: MediaView()
                case .monitor: MonitorView()
                case .me: MeView(cognitive: chatModel.cognitive, memory: chatModel.memory, skills: chatModel.skills, practice: chatModel.practice)
                }
            }
                .frame(maxWidth: 960)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if sizeClass != .regular && !keyboardVisible { CustomTabBar() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .task {
            chatModel.awaken()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                chatModel.awaken()
                if scenePhase == .active, appState.currentTab == .chat, !chatModel.isTyping,
                   !NexusLinuxRuntime.shared.isExecuting, chatModel.practice.due {
                    chatModel.practice.start()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { chatModel.practice.stop(); chatModel.leave() }
            else { chatModel.notice() }
        }
        .onChange(of: allowExecution) { _, enabled in
            if !enabled {
                NexusLinuxRuntime.shared.cancelActive(reason: "内置执行已关闭")
                if chatModel.isTyping { chatModel.cancel() }
            }
        }
        .onChange(of: appState.currentTab) { _, tab in if tab != .chat { chatModel.practice.stop() } }
    }
}

struct CustomTabBar: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    appState.haptic(.light)
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) {
                        appState.currentTab = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 20, weight: .medium))
                        Text(tab.titleKey).font(.caption2.weight(.semibold)).lineLimit(1)
                    }
                    .foregroundStyle(appState.currentTab == tab ? Color.bgJadeHi : Color.bgTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(appState.currentTab == tab ? Color.bgJade.opacity(0.17) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(appState.currentTab == tab ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(6)
        .bgFloating(cornerRadius: 26)
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
        .background(Color.bgDark.opacity(0.98).ignoresSafeArea(edges: .bottom))
    }
}

private struct BGSidebar: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Color.bgJadeHi).font(.title2)
                Text("BLACK GOD").font(.headline).tracking(1)
            }.padding(.top, 20).padding(.horizontal, 12)
            VStack(spacing: 8) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    Button { appState.haptic(.light); appState.currentTab = tab } label: {
                        Label(tab.titleKey, systemImage: tab.icon)
                            .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .foregroundStyle(appState.currentTab == tab ? Color.bgJadeHi : Color.bgTextSecondary)
                            .background(appState.currentTab == tab ? Color.bgJade.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(appState.currentTab == tab ? .isSelected : [])
                    .accessibilityIdentifier("tab.\(tab.rawValue)")
                }
            }
            Spacer()
        }
        .padding(16).frame(width: 212)
        .background(Color.bgCard.opacity(0.65))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.bgBorder).frame(width: 1) }
    }
}
