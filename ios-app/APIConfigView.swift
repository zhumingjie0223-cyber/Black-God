//
// APIConfigView.swift — 神枢连接设置
//
// 公开 Worker 地址保存在 AppStorage；主人令牌仅写入 NexusKeychain。
// 旧 api_base/api_key/api_model 项不迁移、不读取、不删除，避免误处理用户已有私密配置。

import SwiftUI

struct APIConfigView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("nexus_base") private var nexusBase = "https://nexus-do.jjiebbay.workers.dev"
    @State private var ownerToken = ""
    @State private var saveError: String?
    @State private var saved = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("神枢 Cloudflare 中枢").font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                        Button {
                            appState.haptic(.light)
                            nexusBase = "https://nexus-do.jjiebbay.workers.dev"
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("生产 Worker").font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
                                    Text("nexus-do.jjiebbay.workers.dev").font(.system(size: 12)).foregroundStyle(Color.bgTextSecondary)
                                }
                                Spacer()
                                if nexusBase == "https://nexus-do.jjiebbay.workers.dev" {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.bgGold)
                                }
                            }
                            .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color.bgCardLight))
                        }
                    }

                    fieldGroup("神枢地址", text: $nexusBase, placeholder: "https://nexus-do.jjiebbay.workers.dev")
                    secureField("主人令牌", text: $ownerToken, placeholder: "仅保存到 iPhone Keychain")

                    if let saveError {
                        Text(saveError).font(.system(size: 12)).foregroundStyle(.red)
                    } else if saved {
                        Text("连接设置已安全保存。令牌不会出现在地址、日志或 AppStorage。")
                            .font(.system(size: 12)).foregroundStyle(Color.bgTextSecondary)
                    }

                    Button {
                        appState.haptic(.medium)
                        save()
                    } label: {
                        Text("保存神枢连接").font(.bgHeadline())
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(LinearGradient.goldGradient).foregroundStyle(Color.bgDark)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.top, 8)

                    Text("聊天、Agent 计划、工作台和设备桥接都会直接请求神枢 Worker。模型凭据与规范对话历史由神枢服务端管理；本机仅保留用于认证的主人令牌，并由 Keychain 保护。")
                        .font(.system(size: 11)).foregroundStyle(Color.bgTextSecondary)
                }
                .padding(20)
            }
            .background(LinearGradient.darkGradient.ignoresSafeArea())
            .navigationTitle("神枢连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }.foregroundStyle(Color.bgGold)
                }
            }
            .onAppear {
                ownerToken = NexusKeychain.read(.ownerToken) ?? ""
            }
        }
    }

    private func save() {
        saveError = nil
        saved = false
        let address = nexusBase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), url.scheme == "https" || url.scheme == "http" else {
            saveError = "神枢地址必须是 http 或 https URL。"
            return
        }
        nexusBase = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        do {
            let token = ownerToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { try NexusKeychain.delete(.ownerToken) }
            else { try NexusKeychain.write(token, for: .ownerToken) }
            saved = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func fieldGroup(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
                .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color.bgCardLight))
        }
    }

    private func secureField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
            SecureField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
                .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color.bgCardLight))
        }
    }
}
