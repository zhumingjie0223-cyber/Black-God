// APIConfigView.swift — API Key 配置界面（多服务商，Key 按服务商分别存 Keychain）

import SwiftUI

struct APIConfigView: View {
    @State private var apiKey: String = ""
    @State private var selectedModel: String = NexusKeychain.shared.selectedModel
    @State private var saved = false
    @State private var showKey = false

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
                    Text("Key 仅存储在本机 Keychain，按服务商分别保存，不上传任何服务器。\n获取 Key：\(provider.keyHint)")
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
            .onAppear { loadKey() }
            .onChange(of: selectedModel) { _, _ in loadKey() }
        }
    }

    private var keyPlaceholder: String {
        provider.type == .anthropic ? "sk-ant-api03-..." : "sk-..."
    }

    private func loadKey() {
        apiKey = NexusKeychain.shared.key(for: provider.id) ?? ""
    }

    private func save() {
        NexusKeychain.shared.setKey(apiKey.trimmingCharacters(in: .whitespaces), for: provider.id)
        NexusKeychain.shared.selectedModel = selectedModel
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}
