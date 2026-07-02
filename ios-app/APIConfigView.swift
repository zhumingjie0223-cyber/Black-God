//
//  APIConfigView.swift — API 配置页（权哥填自己的API）
//

import SwiftUI

struct APIConfigView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("api_base") var apiBase = "https://api.deepseek.com/v1"
    @AppStorage("api_key") var apiKey = ""
    @AppStorage("api_model") var apiModel = "deepseek-chat"
    @Environment(\.dismiss) var dismiss

    // 常用 API 预设
    let presets: [(String, String, String)] = [
        ("DeepSeek", "https://api.deepseek.com/v1", "deepseek-chat"),
        ("火山方舟", "https://ark.cn-beijing.volces.com/api/v3", "你的endpoint-id"),
        ("OpenAI", "https://api.openai.com/v1", "gpt-4o"),
        ("Claude中转", "https://api.lufei.uk/v1", "Black God 智能【自动选最优】")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 快速预设
                    VStack(alignment: .leading, spacing: 10) {
                        Text("快速选择").font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                        ForEach(presets, id: \.0) { preset in
                            Button {
                                appState.haptic(.light)
                                apiBase = preset.1
                                apiModel = preset.2
                            } label: {
                                HStack {
                                    Text(preset.0).font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
                                    Spacer()
                                    if apiBase == preset.1 {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.bgGold)
                                    }
                                }
                                .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color.bgCardLight))
                            }
                        }
                    }

                    // API 地址
                    fieldGroup("API 地址", text: $apiBase, placeholder: "https://...")
                    // API Key
                    fieldGroup("API Key", text: $apiKey, placeholder: "sk-...", secure: true)
                    // 模型名
                    fieldGroup("模型名", text: $apiModel, placeholder: "deepseek-chat")

                    // 保存
                    Button {
                        appState.haptic(.medium)
                        dismiss()
                    } label: {
                        Text("保存").font(.bgHeadline())
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(LinearGradient.goldGradient).foregroundStyle(Color.bgDark)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.top, 8)

                    Text("API 由你自己提供，配置只存在本机，不上传任何服务器")
                        .font(.system(size: 11)).foregroundStyle(Color.bgTextSecondary)
                }
                .padding(20)
            }
            .background(LinearGradient.darkGradient.ignoresSafeArea())
            .navigationTitle("API 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }.foregroundStyle(Color.bgGold)
                }
            }
        }
    }

    func fieldGroup(_ label: String, text: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
            .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color.bgCardLight))
        }
    }
}
