//
//  MediaView.swift — 创作页（生图/生视频/语音）
//

import SwiftUI
import UIKit

struct MediaView: View {
    @EnvironmentObject var appState: AppState
    @State private var prompt = ""
    @State private var selectedMode = 0
    @State private var copied = false
    @State private var showHints = false
    @FocusState private var editingPrompt: Bool
    let modes = ["生图", "生视频", "语音"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("创作").font(.title2.weight(.semibold)).foregroundStyle(Color.bgTextPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("灵感草稿").font(.caption).foregroundStyle(Color.bgTextSecondary)
                    }
                    Spacer(minLength: 0)
                    BGAuraOrb(diameter: 112).allowsHitTesting(false).accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Picker("创作类型", selection: $selectedMode) {
                        ForEach(0..<modes.count, id: \.self) { i in Text(modes[i]).tag(i) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("media.mode")
                    TextField(placeholder, text: $prompt, axis: .vertical)
                        .focused($editingPrompt)
                        .font(.bgBody()).foregroundStyle(Color.bgTextPrimary).lineLimit(5...10)
                        .padding(14).background(Color.bgDark.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(selectedMode == 2 ? "语音文案" : "创意描述")
                        .accessibilityIdentifier("media.prompt")
                    Button {
                        UIPasteboard.general.string = prompt
                        editingPrompt = false
                        appState.haptic(.light)
                        copied = true
                    } label: {
                        Label(copied ? "已复制描述" : "复制描述", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(BGPrimaryButtonStyle())
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("media.copy")
                    Button {} label: {
                        Label("生成服务尚未接入", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }.buttonStyle(BGSecondaryButtonStyle()).disabled(true)
                    .accessibilityHint("生成服务尚未接入，当前可编辑和复制描述")
                    .accessibilityIdentifier("media.generate")
                }.padding(18).bgFloating()

                DisclosureGroup(isExpanded: $showHints) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(writingHints, id: \.self) { hint in
                            Text(hint).font(.caption).foregroundStyle(Color.bgTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                } label: {
                    Label("写作提示", systemImage: "lightbulb")
                        .font(.subheadline).foregroundStyle(Color.bgTextSecondary).frame(minHeight: 44)
                }
                .tint(Color.bgJadeHi)
                .padding(.horizontal, 18).padding(.vertical, 4).bgFloating(cornerRadius: 20)
            }
            .padding(20)
        }
        .background(Color.bgDark)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: prompt) { _, _ in copied = false }
        .onChange(of: selectedMode) { _, _ in copied = false }
    }

    var placeholder: String {
        switch selectedMode {
        case 0: return "描述你想看到的画面…"
        case 1: return "写下镜头、动作与时长…"
        default: return "输入语音文案…"
        }
    }

    private var writingHints: [String] {
        switch selectedMode {
        case 0: return ["主体与环境", "光线、色彩与构图", "用途与关键细节"]
        case 1: return ["用途与目标时长", "镜头顺序与动作", "节奏、配色与字幕"]
        default: return ["完整朗读文案", "语速、语气与情绪", "发音与停顿位置"]
        }
    }
}
