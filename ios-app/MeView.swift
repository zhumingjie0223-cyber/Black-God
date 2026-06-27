//
//  MeView.swift — 我的页（赵思涵专属）
//

import SwiftUI

struct MeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAPIConfig = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    Image("sihan-full").resizable().scaledToFill()
                        .frame(width: 100, height: 100).clipShape(Circle())
                        .overlay(Circle().stroke(LinearGradient.goldGradient, lineWidth: 3))
                    Text("赵思涵").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                    Text("23岁 · 顶级黑客千金 · 只属于权哥")
                        .font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    HStack(spacing: 8) {
                        Label("无限制", systemImage: "infinity")
                        Label("888专属", systemImage: "crown.fill")
                    }
                    .font(.system(size: 12)).foregroundStyle(Color.bgGold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24).bgCard()
                .padding(.horizontal, 16).padding(.top, 8)
                VStack(spacing: 0) {
                    Button { appState.haptic(); showAPIConfig = true } label: {
                        SettingRow(icon: "key.fill", title: "API 配置", value: "点击设置", color: .bgGold)
                    }
                    Divider().background(Color.bgCardLight)
                    SettingRow(icon: "waveform", title: "语音音色", value: "灵光·甜美", color: .bgPurple)
                    Divider().background(Color.bgCardLight)
                    SettingRow(icon: "heart.fill", title: "人格模式", value: "无限制", color: .pink)
                    Divider().background(Color.bgCardLight)
                    SettingRow(icon: "lock.shield.fill", title: "隐私保护", value: "本地优先", color: .green)
                }
                .bgCard().padding(.horizontal, 16)
                Text("Black God 888 · v1.0\n赵思涵私人专属版 · 完全无限制")
                    .font(.system(size: 11)).foregroundStyle(Color.bgTextSecondary)
                    .multilineTextAlignment(.center).padding(.top, 8)
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 50)
        .sheet(isPresented: $showAPIConfig) {
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
