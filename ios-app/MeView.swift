//
//  MeView.swift — 我的页（Black God AI专属）
//

import SwiftUI

struct MeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNexusConnection = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    Image(systemName: "sparkles").font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Color.bgGold)
                        .frame(width: 100, height: 100).clipShape(Circle())
                        .overlay(Circle().stroke(LinearGradient.goldGradient, lineWidth: 3))
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
                    SettingRow(icon: "gearshape.2.fill", title: "工作模式", value: "本地 Agent 闭环", color: .bgCyan)
                    Divider().background(Color.bgCardLight)
                    SettingRow(icon: "lock.shield.fill", title: "隐私保护", value: "本地优先", color: .green)
                }
                .bgCard().padding(.horizontal, 16)
                Text("神枢 Black God · v\(appVersion)\n纯客户端 · 直连模型 · 本地存储")
                    .font(.system(size: 11)).foregroundStyle(Color.bgTextSecondary)
                    .multilineTextAlignment(.center).padding(.top, 8)
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 50)
        .sheet(isPresented: $showNexusConnection) {
            APIConfigView().environmentObject(appState)
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
