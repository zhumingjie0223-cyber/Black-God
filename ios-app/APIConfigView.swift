import SwiftUI

struct APIConfigView: View {
    @StateObject private var oauth = NexusOAuthLogin()
    @State private var oauthConnected = false
    @State private var oauthSessionID: String?
    @State private var workspaceID = ""
    @State private var sharingAllowed = false
    @State private var apiKey: String
    @State private var modelID: String
    @State private var baseURL: String
    @State private var protocolType: NexusProviderType
    @State private var presetID: String
    @State private var nativeTools: Bool
    @State private var connectionID: String
    @State private var label: String
    @State private var savedConnections: [NexusModelEntry] = NexusKeychain.shared.savedConnections
    @State private var selectedSavedID = ""
    @State private var remoteModels: [NexusRemoteModel] = []
    @State private var saved = false
    @State private var saveError: String?
    @State private var showKey = false
    @State private var diagnostic: String?
    @State private var isTesting = false
    @State private var testTask: Task<Void, Never>?

    private static var presets: [NexusProviderPreset] { NexusProviderPresets.all }
    init() {
        let entry = NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel)
        _workspaceID = State(initialValue: entry.anthropicWorkspaceID ?? "")
        _sharingAllowed = State(initialValue: NexusDataConsent.shared.allows(entry))
        _oauthSessionID = State(initialValue: entry.oauthSessionID)
        _oauthConnected = State(initialValue: NexusKeychain.shared.isOAuth(entry.credentialID))
        _connectionID = State(initialValue: entry.connectionID ?? UUID().uuidString)
        _label = State(initialValue: entry.displayName)
        _apiKey = State(initialValue: NexusKeychain.shared.key(for: entry.credentialID) ?? "")
        _nativeTools = State(initialValue: entry.usesNativeTools)
        _modelID = State(initialValue: entry.modelID)
        _baseURL = State(initialValue: entry.providerURL)
        _protocolType = State(initialValue: entry.providerType)
        _presetID = State(initialValue: Self.presets.contains(where: { $0.id == entry.providerID }) ? entry.providerID : "custom")
    }
    private var connection: NexusModelEntry {
        let preset = Self.presets.first { $0.id == presetID }
        return NexusModelEntry(providerID: preset?.id ?? NexusEndpoint.credentialID(base: baseURL, type: protocolType),
            providerType: protocolType, providerURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? modelID : label,
            isHidden: false, nativeToolCalling: nativeTools, connectionID: connectionID, oauthSessionID: oauthSessionID, anthropicWorkspaceID: workspaceID.isEmpty ? nil : workspaceID)
    }

    private var valid: Bool {
        !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && connection.validWorkspace && NexusEndpoint.requestURL(for: connection) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("OAuth 账号登录") {
                    Button("使用 OpenRouter 账号登录") {
                        selectPreset("openrouter")
                        oauth.start(entry: connection)
                    }.disabled(isTesting || oauth.isRunning).accessibilityIdentifier("oauth.login")
                    ForEach(NexusDeviceProvider.allCases) { provider in
                        Button("使用 " + provider.name + " 账号登录") {
                            selectPreset(provider.rawValue)
                            oauth.startDevice(provider, entry: connection)
                        }.disabled(isTesting || oauth.isRunning).accessibilityIdentifier("oauth." + provider.rawValue)
                    }
                    if let code = oauth.userCode {
                        LabeledContent("设备验证码", value: code).textSelection(.enabled)
                        Button("重新打开授权页面") { oauth.reopenBrowser() }
                    }
                    if oauth.isRunning {
                        ProgressView()
                        Button("取消登录") { oauth.cancel() }.accessibilityIdentifier("oauth.cancel")
                    }
                    if !oauth.status.isEmpty { Text(oauth.status).font(.footnote).accessibilityIdentifier("oauth.status") }
                    Text("在服务商页面登录后自动保存凭据，无需复制密钥。Kimi、Grok 和 MiniMax 使用公开 CLI 授权流程，授权页可能显示 Kimi Code、Grok CLI 或 MiniMax CLI。实际权限以服务商为准，尚未完成真实账号验收。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if oauthConnected {
                        Label("此连接已通过 OAuth 登录", systemImage: "checkmark.shield")
                        Button("断开此连接", role: .destructive) {
                            do {
                                NexusDataConsent.shared.set(false, for: connection); sharingAllowed = false
                                try NexusKeychain.shared.disconnectOAuth(connection.credentialID)
                                apiKey = ""; oauthSessionID = nil; oauthConnected = false; saved = false
                                diagnostic = "已清除此设备的凭据。服务商端撤销请在对应账号的授权管理页操作。"
                            } catch { saveError = error.localizedDescription }
                        }.disabled(isTesting || oauth.isRunning).accessibilityIdentifier("oauth.disconnect")
                        if presetID == "openrouter" {
                            Link("管理 OpenRouter 授权", destination: URL(string: "https://openrouter.ai/keys")!)
                        }
                    }
                }
                if let provider = NexusDeviceProvider(rawValue: presetID), connection.oauthSessionID != nil {
                    Button("重新授权此连接") { oauth.startDevice(provider, entry: connection) }
                        .disabled(isTesting || oauth.isRunning)
                }
                Section("Claude 接入") {
                    Button("配置 Claude 官方 API") { selectPreset("anthropic") }
                        .accessibilityIdentifier("claude.api")
                    Text("使用 Anthropic API 密钥，支持对话、模型列表和原生工具调用。Claude.ai 订阅登录不用于本应用的原生接口。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("打开 Claude Console", destination: URL(string: "https://platform.claude.com/settings/keys")!)
                    Text("如需账号登录，可使用上方 OpenRouter，然后选择账号有权限的 Claude 模型；使用的是 OpenRouter 额度。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(isTesting || oauth.isRunning)
                if !savedConnections.isEmpty {
                    Section("已保存连接") {
                        Picker("打开连接", selection: Binding(get: { selectedSavedID }, set: { id in
                            selectedSavedID = id
                            if let entry = savedConnections.first(where: { $0.id == id }) { load(entry) }
                        })) {
                            Text("选择已保存的连接").tag("")
                            ForEach(savedConnections) { entry in
                                Text(entry.displayName + " · " + entry.modelID).tag(entry.id)
                            }
                        }.accessibilityIdentifier("api.saved")
                        Text("打开配置后点击“保存并使用”，即可切换当前模型。进行中的任务继续使用发送时的连接。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.disabled(isTesting || oauth.isRunning)
                }
                Section("服务商") {
                    Picker("预设", selection: Binding(get: { presetID }, set: { selectPreset($0) })) {
                        ForEach(Self.presets) { entry in Text(entry.name).tag(entry.id) }
                        Text("自定义接口").tag("custom")
                    }.accessibilityIdentifier("api.provider")
                    TextField("连接名称，例如工作账号", text: $label).accessibilityIdentifier("api.label")
                    Button("新增同类连接") { selectPreset(presetID) }.accessibilityIdentifier("api.new")
                    if let preset = Self.presets.first(where: { $0.id == presetID }) {
                        Text(preset.note).font(.footnote).foregroundStyle(.secondary)
                        if let url = URL(string: preset.documentation) { Link("服务商接入文档", destination: url) }
                    }
                    Picker("接口协议", selection: Binding(get: { protocolType }, set: { protocolType = $0; destinationChanged() })) {
                        Text("Anthropic Messages").tag(NexusProviderType.anthropic)
                        Text("OpenAI Chat Completions").tag(NexusProviderType.openAICompatible)
                        Text("OpenAI Responses").tag(NexusProviderType.responses)
                        Text("Gemini 原生").tag(NexusProviderType.gemini)
                    }
                    TextField("HTTPS 接口地址", text: Binding(get: { baseURL }, set: { baseURL = $0; destinationChanged() }))
                        .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL).accessibilityIdentifier("api.base")
                    TextField("服务商提供的模型名称", text: $modelID).accessibilityIdentifier("api.model")
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("获取模型列表") {
                        let entry = connection, key = apiKey
                        isTesting = true
                        diagnostic = "正在读取此账号的模型列表…"
                        testTask = Task {
                            defer { isTesting = false; testTask = nil }
                            do {
                                remoteModels = try await NexusClient.shared.fetchModels(entry: entry, apiKey: key)
                                diagnostic = "已获取 \(remoteModels.count) 个模型；请选择聊天模型。列表不代表已通过调用测试。"
                            } catch is CancellationError { diagnostic = "已取消。" }
                            catch { diagnostic = error.localizedDescription + " 模型列表不可用时，可以手动填写模型 ID。" }
                        }
                    }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || NexusModelsAPI.endpoint(connection) == nil)
                        .accessibilityIdentifier("api.models")
                    if !remoteModels.isEmpty {
                        Picker("选择模型", selection: $modelID) {
                            Text(modelID.isEmpty ? "请选择模型" : modelID).tag(modelID)
                            ForEach(remoteModels.filter { $0.id != modelID }) { model in Text(model.name + " · " + model.id).tag(model.id) }
                        }
                    }
                    if presetID == "anthropic" {
                        TextField("Workspace ID（多工作区密钥需要）", text: Binding(get: { workspaceID }, set: {
                            workspaceID = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            sharingAllowed = NexusDataConsent.shared.allows(connection); saved = false
                        })).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("claude.workspace")
                    }
                    Toggle("原生工具调用", isOn: $nativeTools)
                    Text("模型支持工具调用时开启。若接口不支持，可关闭以使用文本兼容模式。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(isTesting || oauth.isRunning)
                if !oauthConnected {
                Section {
                    HStack {
                        Group {
                            if showKey { TextField("输入服务商密钥", text: $apiKey) }
                            else { SecureField("输入服务商密钥", text: $apiKey) }
                        }.autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                            .accessibilityLabel(showKey ? "隐藏密钥" : "显示密钥")
                    }
                } header: { Text("连接密钥") } footer: {
                    Text("密钥保存在本机钥匙串。请求会将相关对话与密钥发送到上方地址。修改地址或协议后请重新填入该接口的密钥。")
                }.disabled(isTesting || oauth.isRunning)
                }
                Section("向模型发送内容") {
                    Text("接收方：" + baseURL).font(.footnote).textSelection(.enabled)
                    Text("请求会发送当前对话、选用的长期记忆、技能指令及工具结果；它们可能包含个人信息或文件内容。认证凭据发送至配置的服务商；其保留和使用规则由服务商决定。关闭许可会阻止后续模型请求，不会撤回已发送内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("允许向此连接发送上述内容", isOn: Binding(get: { sharingAllowed }, set: {
                        sharingAllowed = $0; NexusDataConsent.shared.set($0, for: connection)
                    })).accessibilityIdentifier("api.data-consent")
                }.disabled(isTesting || oauth.isRunning || NexusEndpoint.requestURL(for: connection) == nil)
                Section {
                    Button(saved ? "当前连接已保存" : "保存并使用") {
                        do {
                            try NexusKeychain.shared.saveConnection(connection, apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                            saved = true
                            savedConnections = NexusKeychain.shared.savedConnections
                            selectedSavedID = connection.id
                        } catch { saveError = error.localizedDescription }
                    }.disabled(!valid || isTesting || oauth.isRunning)
                    Button(isTesting ? "取消连接测试" : "测试连接") {
                        if isTesting { testTask?.cancel(); return }
                        let entry = connection
                        let key = apiKey
                        isTesting = true
                        diagnostic = "正在检查认证、模型与完整响应…"
                        testTask = Task {
                            defer { isTesting = false; testTask = nil }
                            do {
                                let start = Date()
                                _ = try await NexusClient.shared.complete(messages: [ChatMessage(role: "user", content: "仅回复 OK")], entry: entry, apiKey: key)
                                diagnostic = "连接成功：模型返回了完整回答（\(String(format: "%.1f", Date().timeIntervalSince(start))) 秒）。"
                            } catch is CancellationError { diagnostic = "已取消测试。" }
                            catch { diagnostic = error.localizedDescription }
                        }
                    }.disabled(oauth.isRunning || (!isTesting && (!sharingAllowed || !valid || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                    Button("测试工具执行") {
                        let entry = connection
                        let key = apiKey
                        isTesting = true
                        diagnostic = "正在验证模型调用计算器及结果回传…"
                        testTask = Task {
                            defer { isTesting = false; testTask = nil }
                            do {
                                var tools = NexusToolRegistry()
                                tools.register(NexusCalculatorTool())
                                let messages: [NexusNativeMessage] = [.text(role: "user", content: "请必须调用 calc 工具计算 3+4，参数 expression 为 3+4。不要自行计算。")]
                                let reply = try await NexusClient.shared.nativeTurn(messages: messages, tools: tools.nativeDefinitions, entry: entry, apiKey: key)
                                guard reply.calls.count == 1, let native = reply.calls.first,
                                      native.call.name == "calc", native.call.arguments == ["expression": "3+4"] else {
                                    throw NexusError.apiError("接口有响应，但模型没有按要求发出计算器调用；尚未通过工具测试。")
                                }
                                try Task.checkCancellation()
                                let result = await tools.execute(native.call)
                                guard result.succeeded, result.output == "7" else { throw NexusError.invalidResponse }
                                let final = try await NexusClient.shared.nativeTurn(messages: messages + [.assistant(reply), .results([(native, result)])], tools: [], entry: entry, apiKey: key)
                                guard final.calls.isEmpty else { throw NexusError.apiError("模型未在工具结果回传后结束回答。") }
                                diagnostic = "工具链路通过：模型发出调用 → 本机算出 7 → 模型收到结果并完成回答。"
                            } catch is CancellationError { diagnostic = "已取消测试。" }
                            catch { diagnostic = error.localizedDescription }
                        }
                    }.disabled(oauth.isRunning || isTesting || !sharingAllowed || !nativeTools || !valid || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let diagnostic { Text(diagnostic).font(.footnote).textSelection(.enabled) }
                } footer: { Text("连接测试发送一次请求；工具测试发送两次请求并在本机执行一次计算。可能消耗服务商额度，不会自动保存配置。") }
            }
            .navigationTitle("模型连接")
            .tint(Color.bgCyan)
            .background(NexusOAuthSafariPresenter(browser: oauth.browser, onCancel: { oauth.browserDismissed() })
                .frame(width: 0, height: 0))
            .onChange(of: oauth.completedEntry) { _, entry in
                guard let entry else { return }
                load(entry)
                savedConnections = NexusKeychain.shared.savedConnections
                selectedSavedID = entry.id
                fetchOAuthModels(entry)
            }
            .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("确定") { saveError = nil }
            } message: { Text(saveError ?? "") }
            .onChange(of: nativeTools) { _, _ in saved = false; diagnostic = nil }
            .onChange(of: label) { _, _ in saved = false }
            .onChange(of: modelID) { _, _ in saved = false; diagnostic = nil }
            .onChange(of: apiKey) { _, _ in saved = false; diagnostic = nil; remoteModels = [] }
            .onDisappear { testTask?.cancel(); oauth.cancel() }
        }
    }
    private func fetchOAuthModels(_ entry: NexusModelEntry) {
        let key = NexusKeychain.shared.key(for: entry.credentialID) ?? ""
        isTesting = true
        testTask = Task {
            defer { isTesting = false; testTask = nil }
            do {
                let models = try await NexusClient.shared.fetchModels(entry: entry, apiKey: key)
                try Task.checkCancellation()
                remoteModels = models
                diagnostic = "登录已保存。请选择模型并点击“保存并使用”；未发送生成请求。"
            } catch is CancellationError { diagnostic = "模型列表读取已取消，登录凭据已保存。" }
            catch { diagnostic = "登录凭据已保存，但模型列表暂不可用。可重试或手动填写账号支持的模型 ID。" }
        }
    }
    private func load(_ entry: NexusModelEntry) {
        presetID = Self.presets.contains(where: { $0.id == entry.providerID }) ? entry.providerID : "custom"
        workspaceID = entry.anthropicWorkspaceID ?? ""
        sharingAllowed = NexusDataConsent.shared.allows(entry)
        oauthSessionID = entry.oauthSessionID
        connectionID = entry.connectionID ?? UUID().uuidString
        label = entry.displayName
        baseURL = entry.providerURL
        modelID = entry.modelID
        protocolType = entry.providerType
        nativeTools = entry.usesNativeTools
        apiKey = NexusKeychain.shared.key(for: entry.credentialID) ?? ""
        oauthConnected = NexusKeychain.shared.isOAuth(entry.credentialID)
        saved = false
        remoteModels = []
        diagnostic = nil
    }
    private func selectPreset(_ id: String) {
        oauthConnected = false; oauthSessionID = nil; workspaceID = ""; sharingAllowed = false
        presetID = id
        connectionID = UUID().uuidString
        selectedSavedID = ""
        let preset = Self.presets.first { $0.id == id }
        label = preset?.name ?? "自定义连接"
        baseURL = preset?.baseURL ?? ""
        protocolType = preset?.type ?? .openAICompatible
        modelID = ""
        apiKey = ""
        nativeTools = true
        saved = false
        remoteModels = []
        diagnostic = nil
    }
    private func destinationChanged() {
        oauthConnected = false; oauthSessionID = nil; workspaceID = ""; sharingAllowed = false
        remoteModels = []
        apiKey = ""
        saved = false
        diagnostic = nil
    }
}
