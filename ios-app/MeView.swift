//
//  MeView.swift — 我的页（Black God AI专属）
//

import SwiftUI

struct MeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var cognitive: NexusCognitiveControl
    @State private var showCognitive = false
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
    @State private var showAdvanced = false
    @State private var showMemory = false
    @State private var showNexusConnection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("我的").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.vertical, 4)

                settingsGroup("连接") {
                    Button { appState.haptic(); showNexusConnection = true } label: {
                        SettingRow(icon: "network", title: "神枢连接", value: "", color: .bgJadeHi, compact: true)
                    }
                    .accessibilityIdentifier("api.open")
                }

                settingsGroup("能力") {
                    Button { showMemory = true } label: {
                        SettingRow(icon: "brain.head.profile", title: "长期记忆", value: "\(memory.curated.count) 条", color: .bgJadeHi, compact: true)
                    }.accessibilityIdentifier("memory.open")
                    Divider().overlay(Color.bgCardLight)
                    Button { showSkills = true } label: {
                        SettingRow(icon: "list.bullet.rectangle", title: "任务技能", value: "\(skills.items.count) 个", color: .bgJadeHi, compact: true)
                    }.accessibilityIdentifier("skills.open")
                    Divider().overlay(Color.bgCardLight)
                    Button { showCognitive = true } label: {
                        SettingRow(icon: "checkmark.shield", title: "神枢成长", value: "", color: .bgJadeHi, compact: true)
                    }.accessibilityIdentifier("cognitive.open")
                }

                settingsGroup("设置") {
                    Button { showAdvanced = true } label: {
                        SettingRow(icon: "slider.horizontal.3", title: "高级设置", value: "", color: .bgJadeHi, compact: true)
                    }.accessibilityIdentifier("advanced.open")
                    Divider().overlay(Color.bgCardLight)
                    Button { showPrivacy = true } label: {
                        SettingRow(icon: "lock.shield", title: "隐私保护", value: "", color: .bgJadeHi, compact: true)
                    }.accessibilityIdentifier("privacy.open")
                    Divider().overlay(Color.bgCardLight)
                    Button { showLicenses = true } label: {
                        SettingRow(icon: "doc.text", title: "开源许可", value: "", color: .bgJadeHi, compact: true)
                    }.accessibilityIdentifier("licenses.open")
                }

                HStack {
                    Text("Black God")
                    Spacer()
                    Text(version).accessibilityIdentifier("app.version")
                }
                .font(.caption)
                .foregroundStyle(Color.bgTextSecondary)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.bgDark)
        .sheet(isPresented: $showCognitive) { NexusCognitiveView(control: cognitive) }
        .sheet(isPresented: $showPrivacy) { NexusPrivacyView() }
        .sheet(isPresented: $showLicenses) { NexusPrivacyView(resource: "OPEN_SOURCE_LICENSES", title: "开源许可") }
        .sheet(isPresented: $showSkills) { NexusSkillsView(store: skills, practice: practice) }
        .sheet(isPresented: $showAdvanced) { NexusAdvancedSettingsView() }
        .sheet(isPresented: $showMemory) { NexusMemoryView(memory: memory) }
        .sheet(isPresented: $showNexusConnection) {
            APIConfigView().environmentObject(appState)
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.bgTextSecondary)
                .padding(.leading, 4)
            VStack(spacing: 0, content: content)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .bgFloating()
        }
    }

}

struct SettingRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    var compact = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(width: compact ? 36 : 42, height: compact ? 36 : 42)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.bgTextPrimary)
                if !compact, !value.isEmpty {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(Color.bgTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if compact, !value.isEmpty {
                Text(value).font(.caption.monospacedDigit()).foregroundStyle(Color.bgTextSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.bgTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
