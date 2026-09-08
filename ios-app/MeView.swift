//
//  MeView.swift — 我的页（Black God AI专属）
//

import SwiftUI

struct MeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vm: ChatViewModel
    @State private var showNexusConnection = false
    @State private var showWipeConfirm = false
    @State private var showWipeDone = false
    @State private var showPrivacy = false
    @State private var showMemory = false
    @State private var wipeErrors: [String] = []

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    Image("BrandMark").resizable().scaledToFit()
                        .frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 24))
                    Text("Black God AI").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                    Text("Black God AI 助手 · 为你工作")
                        .font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    HStack(spacing: 8) {
                        Label("神枢", systemImage: "infinity")
                        Label("纯客户端", systemImage: "lock.fill")
                    }
                    .font(.system(size: 12)).foregroundStyle(Color.bgGold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24).bgCard()
                .padding(.horizontal, 16).padding(.top, 8)
                VStack(spacing: 0) {
                    Button { appState.haptic(); showNexusConnection = true } label: {
                        SettingRow(icon: "key.fill", title: "API 配置", value: "直连模型 · Keychain", color: .bgGold)
                    }
                    Divider().background(Color.bgCardLight)
                    Button { showMemory = true } label: {
                        SettingRow(icon: "bookmark.fill", title: "记忆管理", value: "由你收藏 · 随时删除", color: .bgCyan)
                    }
                    Divider().background(Color.bgCardLight)
                    Button { showPrivacy = true } label: {
                        SettingRow(icon: "lock.shield.fill", title: "隐私政策", value: "数据与服务商", color: .green)
                    }
                }
                .bgCard().padding(.horizontal, 16)
                VStack(spacing: 0) {
                    Button(role: .destructive) { appState.haptic(); showWipeConfirm = true } label: {
                        SettingRow(icon: "trash.fill", title: "清除全部数据", value: "Key · 记忆 · 记录", color: .red)
                    }
                }
                .bgCard().padding(.horizontal, 16)
                Text("神枢 Black God · v\(appVersion)\n纯客户端 · 直连模型 · 本地存储")
                    .font(.system(size: 11)).foregroundStyle(Color.bgTextSecondary)
                    .multilineTextAlignment(.center).padding(.top, 8)
            }
            .padding(.bottom, 24)
        }
        .padding(.top, 12)
        .sheet(isPresented: $showNexusConnection) {
            APIConfigView().environmentObject(appState)
        }
        .sheet(isPresented: $showPrivacy) { NexusPrivacyView() }
        .sheet(isPresented: $showMemory) { NexusMemoryView(store: vm.memory) }
        .alert("清除全部数据？", isPresented: $showWipeConfirm) {
            Button("清除", role: .destructive) {
                vm.resetAfterWipe()
                wipeErrors = NexusDataReset.wipeAll()
                showWipeDone = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除本机保存的全部 API Key、所选模型、记忆、运行记录与工具产物。此操作不可撤销。它不会删除 AI 服务商保存的副本或设备备份中的数据。")
        }
        .alert(wipeErrors.isEmpty ? "已清除" : "部分数据未能清除", isPresented: $showWipeDone) {
            Button("好", role: .cancel) {}
        } message: {
            Text(wipeErrors.isEmpty ? "本机数据已清除。服务商副本和设备备份需另行管理。" : wipeErrors.joined(separator: "\n"))
        }
    }
}

struct SettingRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color).frame(width: 28)
            Text(title).font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
            Spacer()
            Text(value).font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Color.bgTextSecondary)
        }
        .padding(.vertical, 14).padding(.horizontal, 4)
    }
}
