// APIConfigView.swift — API Key 配置界面（多服务商，Key 按服务商分别存 Keychain）

import SwiftUI

struct APIConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?
    @State private var apiKey: String = ""
    @State private var selectedModel: String = NexusKeychain.shared.selectedModel
    @State private var saved = false
    @State private var showKey = false
    @State private var sharingConsent = false
    @State private var providerDrafts: [String: (String, Bool)] = [:]

    private let entries = NexusModelCatalog.entries

    private var provider: NexusProviderInfo {
        NexusModelCatalog.provider(for: NexusModelCatalog.entry(for: selectedModel).providerID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if showKey {
                            TextField(keyPlaceholder, text: $apiKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField(keyPlaceholder, text: $apiKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("\(provider.displayName) API Key")
                } footer: {
                    Text("Key 保存在本机 Keychain，请求时仅发送给对应服务商用于身份验证。\n获取 Key：\(provider.keyHint)")
                        .font(.caption)
                }

                Section("模型") {
                    Picker("选择模型", selection: $selectedModel) {
                        ForEach(entries) { entry in
                            Text(entry.displayName).tag(entry.modelID)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Toggle("允许发送给 \(provider.displayName)", isOn: $sharingConsent)
                } header: {
                    Text("AI 数据共享")
                } footer: {
                    Text("使用该服务时，你的输入、相关本地记忆和任务上下文会通过 HTTPS 发送至 \(provider.url)，API Key 用于验证请求。服务商可能按其政策保留数据；API 调用可能产生费用。保存前可选择是否同意，之后可在此撤回。AI 回答可能有误，请核对重要信息。")
                }

                if let saveError { Text(saveError).foregroundStyle(.orange) }
                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            Label(saved ? "已保存" : "保存", systemImage: saved ? "checkmark.circle.fill" : "key.fill")
                                .foregroundStyle(saved ? .green : .accentColor)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("API 配置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { loadKey() }
            .onChange(of: selectedModel) { old, new in
                saved = false
                let oldProvider = NexusModelCatalog.entry(for: old).providerID
                let newProvider = NexusModelCatalog.entry(for: new).providerID
                if oldProvider != newProvider {
                    providerDrafts[oldProvider] = (apiKey, sharingConsent)
                    if let draft = providerDrafts[newProvider] { apiKey = draft.0; sharingConsent = draft.1 }
                    else { loadKey() }
                }
            }
        }
    }

    private var keyPlaceholder: String {
        provider.type == .anthropic ? "sk-ant-api03-..." : "sk-..."
    }

    private func loadKey() {
        apiKey = NexusKeychain.shared.key(for: provider.id) ?? ""
        sharingConsent = NexusKeychain.shared.hasSharingConsent(for: provider.id)
    }

    private func save() {
        NexusKeychain.shared.setKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.id)
        NexusKeychain.shared.selectedModel = selectedModel
        NexusKeychain.shared.setSharingConsent(sharingConsent, for: provider.id)
        let expected = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (NexusKeychain.shared.key(for: provider.id) ?? "") == expected,
              NexusKeychain.shared.selectedModel == selectedModel,
              NexusKeychain.shared.hasSharingConsent(for: provider.id) == sharingConsent else {
            saveError = "保存未完成，请解锁设备后重试。"; return
        }
        saveError = nil
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}
