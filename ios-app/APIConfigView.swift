// APIConfigView.swift — API Key 配置界面

import SwiftUI

struct APIConfigView: View {
    @State private var apiKey: String = ""
    @State private var selectedModel: String = NexusKeychain.shared.selectedModel
    @State private var saved = false
    @State private var showKey = false

    private let models = NexusClient.shared.availableModels()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if showKey {
                            TextField("sk-ant-api03-...", text: $apiKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("sk-ant-api03-...", text: $apiKey)
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
                    Text("Anthropic API Key")
                } footer: {
                    Text("Key 仅存储在本机 Keychain，不上传任何服务器。\n获取 Key：console.anthropic.com")
                        .font(.caption)
                }

                Section("模型") {
                    Picker("选择模型", selection: $selectedModel) {
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button {
                        NexusKeychain.shared.apiKey = apiKey.trimmingCharacters(in: .whitespaces)
                        NexusKeychain.shared.selectedModel = selectedModel
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            saved = false
                        }
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
            .onAppear {
                apiKey = NexusKeychain.shared.apiKey ?? ""
            }
        }
    }
}
