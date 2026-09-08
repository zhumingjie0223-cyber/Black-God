//
//  MeView.swift — 我的页（Black God AI专属）
//

import SwiftUI

struct MeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var memory: NexusMemoryStore
    @ObservedObject var skills: NexusSkillStore
    @ObservedObject var practice: NexusSkillPractice
    @State private var showSkills = false
    @State private var showPrivacy = false
    @State private var showLicenses = false
    private var version: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(name)（\(build)）"
    }
    @State private var showMemory = false
    @State private var showNexusConnection = false

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
                        Label("智能助手", systemImage: "crown.fill")
                    }
                    .font(.system(size: 12)).foregroundStyle(Color.bgGold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24).bgCard()
                .padding(.horizontal, 16).padding(.top, 8)
                VStack(spacing: 0) {
                    Button { appState.haptic(); showNexusConnection = true } label: {
                        SettingRow(icon: "shield.lefthalf.filled", title: "神枢连接", value: "OAuth 登录 · 模型直连", color: .bgGold)
                    }
                    .accessibilityIdentifier("api.open")
                    Divider().background(Color.bgCardLight)
                    Button { showMemory = true } label: {
                        SettingRow(icon: "brain.head.profile", title: "长期记忆", value: "\(memory.curated.count)条", color: .bgGold)
                    }.accessibilityIdentifier("memory.open")
                    Divider().background(Color.bgCardLight)
                    Button { showSkills = true } label: {
                        SettingRow(icon: "list.bullet.rectangle", title: "任务技能", value: "\(skills.items.count)个", color: .bgGold)
                    }.accessibilityIdentifier("skills.open")
                    Divider().background(Color.bgCardLight)
                    SettingRow(icon: "heart.fill", title: "助手模式", value: "神枢", color: .pink)
                    Divider().background(Color.bgCardLight)
                    Button { showPrivacy = true } label: { SettingRow(icon: "lock.shield.fill", title: "隐私保护", value: "数据使用说明", color: .green) }.accessibilityIdentifier("privacy.open")
                    Divider().background(Color.bgCardLight)
                    Button { showLicenses = true } label: { SettingRow(icon: "doc.text", title: "开源许可", value: "源码与许可文本", color: .bgGold) }.accessibilityIdentifier("licenses.open")
                }
                .bgCard().padding(.horizontal, 16)
                Text("Black God · \(version)\nBlack God AI私人专属版 · 神枢")
                    .font(.system(size: 11)).foregroundStyle(Color.bgTextSecondary)
                    .multilineTextAlignment(.center).padding(.top, 8)
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 50)
        .sheet(isPresented: $showPrivacy) { NexusPrivacyView() }
        .sheet(isPresented: $showLicenses) { NexusPrivacyView(resource: "OPEN_SOURCE_LICENSES", title: "开源许可") }
        .sheet(isPresented: $showSkills) { NexusSkillsView(store: skills, practice: practice) }
        .sheet(isPresented: $showMemory) { NexusMemoryView(memory: memory) }
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
