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

    @Environment(\.dismiss) private var dismiss
    @State private var diagnosticIsError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionSummary
                    if !savedConnections.isEmpty { savedConnectionCard }
                    accountCard
                    providerCard
                    if !oauthConnected { credentialCard }
                    consentCard
                    diagnosticsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bgDark)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Button(action: saveConnection) {
                        Label(saved ? "当前连接已保存" : "保存并使用", systemImage: saved ? "checkmark.circle.fill" : "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BGPrimaryButtonStyle())
                    .disabled(!valid || isTesting || oauth.isRunning)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Color.bgDark)
                .overlay(alignment: .top) { Divider().overlay(Color.bgCardLight) }
            }
            .navigationTitle("模型连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .toolbarBackground(Color.bgDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Color.bgJadeHi)
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

    private var connectionSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "network")
                .font(.title2).foregroundStyle(Color.bgJadeHi)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.displayName.isEmpty ? "当前配置" : connection.displayName)
                    .font(.headline).foregroundStyle(Color.bgTextPrimary).lineLimit(1)
                Text(modelID.isEmpty ? "尚未选择模型" : modelID)
                    .font(.caption).foregroundStyle(Color.bgTextSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(oauthConnected ? "OAuth 已授权" : apiKey.isEmpty ? "待填密钥" : "已填密钥")
                Text(sharingAllowed ? "发送已允许" : "发送未允许")
                    .foregroundStyle(sharingAllowed ? Color.bgJadeHi : Color.bgTextSecondary)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.bgTextSecondary)
        }
        .padding(14)
        .bgFloating(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("api.summary")
    }

    private var savedConnectionCard: some View {
        connectionCard("已保存连接", icon: "tray.full") {
            Picker("打开连接", selection: Binding(get: { selectedSavedID }, set: { id in
                selectedSavedID = id
                if let entry = savedConnections.first(where: { $0.id == id }) { load(entry) }
            })) {
                Text("选择已保存的连接").tag("")
                ForEach(savedConnections) { entry in
                    Text(entry.displayName + " · " + entry.modelID).tag(entry.id)
                }
            }
            .accessibilityIdentifier("api.saved")
            .pickerStyle(.menu)
            help("切换说明") {
                note("打开配置后点击“保存并使用”，即可切换当前模型。进行中的任务继续使用发送时的连接。")
            }
        }
        .disabled(isTesting || oauth.isRunning)
    }

    private var accountCard: some View {
        connectionCard("账号登录", icon: "person.crop.circle.badge.checkmark") {
            Button {
                selectPreset("openrouter")
                oauth.start(entry: connection)
            } label: {
                Label("使用 OpenRouter 登录", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BGSecondaryButtonStyle())
            .disabled(isTesting || oauth.isRunning)
            .accessibilityIdentifier("oauth.login")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(NexusDeviceProvider.allCases) { provider in
                    Button {
                        selectPreset(provider.rawValue)
                        oauth.startDevice(provider, entry: connection)
                    } label: {
                        Text(provider.name).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BGSecondaryButtonStyle())
                    .disabled(isTesting || oauth.isRunning)
                    .accessibilityIdentifier("oauth." + provider.rawValue)
                    .accessibilityLabel("使用 " + provider.name + " 账号登录")
                }
            }
            if let code = oauth.userCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("设备验证码").font(.caption).foregroundStyle(Color.bgTextSecondary)
                    Text(code).font(.title2.monospaced().weight(.semibold)).textSelection(.enabled)
                    Button("重新打开授权页面") { oauth.reopenBrowser() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.bgDark, in: RoundedRectangle(cornerRadius: 12))
            }
            if oauth.isRunning {
                HStack {
                    ProgressView().tint(Color.bgJadeHi)
                    Text("正在等待服务商授权").font(.footnote)
                    Spacer()
                    Button("取消登录") { oauth.cancel() }.accessibilityIdentifier("oauth.cancel")
                }
            }
            if !oauth.status.isEmpty {
                Label(oauth.status, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.bgTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("oauth.status")
            }
            help("授权说明") {
                note("使用服务商账号授权，无需手动复制密钥；也可以在下方手动配置 API。")
                note("Kimi、Grok 和 MiniMax 使用公开 CLI 授权流程，授权页可能显示 Kimi Code、Grok CLI 或 MiniMax CLI。实际权限以服务商为准，尚未完成真实账号验收。")
            }
            if oauthConnected {
                Divider().overlay(Color.bgCardLight)
                Label("此连接已通过 OAuth 登录", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.bgJadeHi)
                if presetID == "openrouter" {
                    Link("管理 OpenRouter 授权", destination: URL(string: "https://openrouter.ai/keys")!)
                }
                Button("断开此连接", role: .destructive, action: disconnectOAuth)
                    .disabled(isTesting || oauth.isRunning).accessibilityIdentifier("oauth.disconnect")
            }
            if let provider = NexusDeviceProvider(rawValue: presetID), connection.oauthSessionID != nil {
                Button("重新授权此连接") { oauth.startDevice(provider, entry: connection) }
                    .disabled(isTesting || oauth.isRunning)
            }
            Divider().overlay(Color.bgCardLight)
            HStack {
                Text("Claude 官方 API").font(.subheadline.weight(.semibold))
                Spacer()
                Button("配置") { selectPreset("anthropic") }
                    .accessibilityIdentifier("claude.api")
                    .accessibilityLabel("配置 Claude 官方 API")
            }
            .disabled(isTesting || oauth.isRunning)
            help("Claude 接入说明") {
                note("使用 Anthropic API 密钥，支持对话、模型列表和原生工具调用。Claude.ai 订阅登录不用于本应用的原生接口。")
                Link("打开 Claude Console", destination: URL(string: "https://platform.claude.com/settings/keys")!)
                    .font(.footnote).disabled(isTesting || oauth.isRunning)
                note("也可通过 OpenRouter 选择有权限的 Claude 模型，使用 OpenRouter 额度。")
            }
        }
    }

    private var providerCard: some View {
        connectionCard("手动 API", icon: "slider.horizontal.3") {
            Picker("服务商", selection: Binding(get: { presetID }, set: { selectPreset($0) })) {
                ForEach(Self.presets) { entry in Text(entry.name).tag(entry.id) }
                Text("自定义接口").tag("custom")
            }.accessibilityIdentifier("api.provider").pickerStyle(.menu)
            inputField("连接名称") {
                TextField("例如工作账号", text: $label).accessibilityIdentifier("api.label")
            }
            Button { selectPreset(presetID) } label: {
                Label("新增同类连接", systemImage: "plus.circle")
            }.font(.subheadline).accessibilityIdentifier("api.new")
            if let preset = Self.presets.first(where: { $0.id == presetID }) {
                help("服务商说明") {
                    note(preset.note)
                    if let url = URL(string: preset.documentation) {
                        Link("服务商接入文档", destination: url).font(.footnote)
                    }
                }
            }
            Divider().overlay(Color.bgCardLight)
            Picker("接口协议", selection: Binding(get: { protocolType }, set: { protocolType = $0; destinationChanged() })) {
                Text("Anthropic Messages").tag(NexusProviderType.anthropic)
                Text("OpenAI Chat Completions").tag(NexusProviderType.openAICompatible)
                Text("OpenAI Responses").tag(NexusProviderType.responses)
                Text("Gemini 原生").tag(NexusProviderType.gemini)
            }.pickerStyle(.menu)
            inputField("HTTPS 接口地址") {
                TextField("https://", text: Binding(get: { baseURL }, set: { baseURL = $0; destinationChanged() }))
                    .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL).accessibilityIdentifier("api.base")
            }
            inputField("模型名称") {
                TextField("填写服务商提供的模型 ID", text: $modelID).accessibilityIdentifier("api.model")
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            Button(action: fetchModels) {
                Label("获取模型列表", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BGSecondaryButtonStyle())
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || NexusModelsAPI.endpoint(connection) == nil)
            .accessibilityIdentifier("api.models")
            if !remoteModels.isEmpty {
                Picker("选择模型", selection: $modelID) {
                    Text(modelID.isEmpty ? "请选择模型" : modelID).tag(modelID)
                    ForEach(remoteModels.filter { $0.id != modelID }) { model in Text(model.name + " · " + model.id).tag(model.id) }
                }.pickerStyle(.menu)
            }
            if presetID == "anthropic" {
                inputField("Workspace ID · 可选") {
                    TextField("多工作区密钥需要", text: Binding(get: { workspaceID }, set: {
                        workspaceID = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        sharingAllowed = NexusDataConsent.shared.allows(connection); saved = false
                    })).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("claude.workspace")
                }
            }
            Divider().overlay(Color.bgCardLight)
            Toggle("原生工具调用", isOn: $nativeTools)
                .font(.subheadline.weight(.medium))
            help("工具调用说明") {
                note("模型支持工具调用时开启。若接口不支持，可关闭以使用文本兼容模式。")
            }
        }
        .disabled(isTesting || oauth.isRunning)
    }

    private var credentialCard: some View {
        connectionCard("连接密钥", icon: "key.horizontal") {
            inputField("服务商 API 密钥") {
                HStack(spacing: 12) {
                    Group {
                        if showKey { TextField("输入服务商密钥", text: $apiKey) }
                        else { SecureField("输入服务商密钥", text: $apiKey) }
                    }.autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye").frame(width: 28, height: 28)
                    }.accessibilityLabel(showKey ? "隐藏密钥" : "显示密钥")
                }
            }
            help("密钥说明") {
                note("密钥保存在本机钥匙串。请求会将相关对话与密钥发送到配置地址。修改地址或协议后请重新填入该接口的密钥。")
            }
        }
        .disabled(isTesting || oauth.isRunning)
    }

    private var consentCard: some View {
        connectionCard("发送许可", icon: "hand.raised") {
            VStack(alignment: .leading, spacing: 6) {
                Text("内容接收方").font(.caption).foregroundStyle(Color.bgTextSecondary)
                Text(baseURL.isEmpty ? "请先填写接口地址" : baseURL)
                    .font(.footnote.monospaced()).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            note("发送对话、所选记忆、技能与工具结果，可能含个人或文件内容；凭据用于服务商鉴权。")
            Divider().overlay(Color.bgCardLight)
            Toggle("允许向此连接发送上述内容", isOn: Binding(get: { sharingAllowed }, set: {
                sharingAllowed = $0; NexusDataConsent.shared.set($0, for: connection)
            }))
            .font(.subheadline.weight(.medium))
            .accessibilityIdentifier("api.data-consent")
            note("关闭许可阻止新请求，不撤回已发送内容。")
            help("数据使用详情") {
                note("请求会发送当前对话、选用的长期记忆、技能指令及工具结果；它们可能包含个人信息或文件内容。认证凭据发送至配置的服务商；其保留和使用规则由服务商决定。")
            }
        }
        .disabled(isTesting || oauth.isRunning || NexusEndpoint.requestURL(for: connection) == nil)
    }

    private var diagnosticsCard: some View {
        connectionCard("检查连接", icon: "waveform.path.ecg") {
            Button(action: testConnection) {
                Label(isTesting ? "取消连接测试" : "测试连接", systemImage: isTesting ? "stop.circle" : "network")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BGSecondaryButtonStyle())
            .disabled(oauth.isRunning || (!isTesting && (!sharingAllowed || !valid || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
            Button(action: testTools) {
                Label("测试工具执行", systemImage: "wrench.and.screwdriver")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BGSecondaryButtonStyle())
            .disabled(oauth.isRunning || isTesting || !sharingAllowed || !nativeTools || !valid || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let diagnostic {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if isTesting { ProgressView().tint(Color.bgJadeHi) }
                        else { Image(systemName: diagnosticIsError ? "exclamationmark.circle" : "info.circle") }
                        Text(isTesting ? "检查中" : diagnosticIsError ? "需要处理" : "检查结果")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(diagnosticIsError ? Color.orange : Color.bgJadeHi)
                    Text(diagnostic).font(.footnote).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.bgDark, in: RoundedRectangle(cornerRadius: 12))
            }
            note("测试可能消耗额度，不会自动保存配置。")
            help("测试用量") {
                note("连接测试发送一次请求；工具测试发送两次请求并在本机执行一次计算。")
            }
        }
    }

    private func connectionCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline).foregroundStyle(Color.bgTextPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.bgTextPrimary)
        .padding(16)
        .bgFloating()
    }

    private func inputField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(Color.bgTextSecondary)
            content()
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgDark, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func help<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10, content: content)
                .padding(.top, 6)
        } label: {
            Text(title).font(.caption).foregroundStyle(Color.bgTextSecondary)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Color.bgTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func saveConnection() {
        do {
            try NexusKeychain.shared.saveConnection(connection, apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            saved = true
            savedConnections = NexusKeychain.shared.savedConnections
            selectedSavedID = connection.id
        } catch { saveError = error.localizedDescription }

    }

    private func fetchModels() {
        diagnosticIsError = false
        let entry = connection, key = apiKey
        isTesting = true
        diagnostic = "正在读取此账号的模型列表…"
        testTask = Task {
            defer { isTesting = false; testTask = nil }
            do {
                remoteModels = try await NexusClient.shared.fetchModels(entry: entry, apiKey: key)
                diagnostic = "已获取 \(remoteModels.count) 个模型；请选择聊天模型。列表不代表已通过调用测试。"
            } catch is CancellationError { diagnostic = "已取消。" }
            catch { diagnosticIsError = true; diagnostic = error.localizedDescription + " 模型列表不可用时，可以手动填写模型 ID。" }
        }

    }

    private func testConnection() {
        diagnosticIsError = false
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
            catch { diagnosticIsError = true; diagnostic = error.localizedDescription }
        }

    }

    private func testTools() {
        diagnosticIsError = false
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
            catch { diagnosticIsError = true; diagnostic = error.localizedDescription }
        }

    }

    private func disconnectOAuth() {
        diagnosticIsError = false
        do {
            NexusDataConsent.shared.set(false, for: connection); sharingAllowed = false
            try NexusKeychain.shared.disconnectOAuth(connection.credentialID)
            apiKey = ""; oauthSessionID = nil; oauthConnected = false; saved = false
            diagnostic = "已清除此设备的凭据。服务商端撤销请在对应账号的授权管理页操作。"
        } catch { saveError = error.localizedDescription }

    }

    private func fetchOAuthModels(_ entry: NexusModelEntry) {
        diagnosticIsError = false
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
            catch { diagnosticIsError = true; diagnostic = "登录凭据已保存，但模型列表暂不可用。可重试或手动填写账号支持的模型 ID。" }
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
