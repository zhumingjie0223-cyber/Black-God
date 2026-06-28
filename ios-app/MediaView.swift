//
//  MediaView.swift — 创作页（生图/生视频/语音）
//

import SwiftUI

struct MediaView: View {
    @EnvironmentObject var appState: AppState
    @State private var prompt = ""
    @State private var selectedMode = 0
    let modes = ["生图", "生视频", "语音"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("创作").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                    .padding(.horizontal, 16).padding(.top, 8)
                Picker("", selection: $selectedMode) {
                    ForEach(0..<modes.count, id: \.self) { i in Text(modes[i]).tag(i) }
                }
                .pickerStyle(.segmented).padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedMode == 2 ? "要说的话" : "描述你想要的").font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    TextField(placeholder, text: $prompt, axis: .vertical)
                        .font(.bgBody()).foregroundStyle(Color.bgTextPrimary).lineLimit(3...6)
                        .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.bgCardLight))
                }
                .padding(.horizontal, 16)
                Button { appState.haptic(.medium) } label: {
                    HStack {
                        Image(systemName: "sparkles"); Text("生成").font(.bgHeadline())
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(LinearGradient.goldGradient).foregroundStyle(Color.bgDark)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 16)
                if selectedMode != 2 {
                    HStack(spacing: 6) {
                        Image(systemName: "infinity").font(.system(size: 12))
                        Text("888版无限制 · 支持NSFW").font(.system(size: 12))
                    }
                    .foregroundStyle(Color.bgPurple).padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 50)
    }

    var placeholder: String {
        switch selectedMode {
        case 0: return "一个冷白皮黑长直的美女…"
        case 1: return "赵思涵转身回眸的动态镜头…"
        default: return "权哥，今晚想听我说什么～"
        }
    }
}
