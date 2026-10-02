import SwiftUI
import UniformTypeIdentifiers

/// 沙箱主页：首屏一个构图——品牌、一句承诺、玉绿光场、一键点亮。
struct NexusSandboxView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("blackgod.linux.modelTools") private var allowExecution = true
    @AppStorage("blackgod.sandbox.network") private var allowNetwork = true
    @AppStorage("blackgod.sandbox.allowDangerous") private var allowDangerous = false
    @State private var showTerminal = false
    @State private var showStorage = false
    @State private var showControls = false
    @State private var files: [NexusWorkspaceFile] = []
    @State private var quotaText = "配额未读取"
    @State private var imageQuotaText = "整镜像：未读取"
    @State private var status = "本机 Alpine · 尚未点亮"
    @State private var demoPhase = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var importPicker = false
    @State private var exportURL: URL?
    @State private var previewItem: PreviewItem?
    @State private var confirmClear = false
    @State private var clearPhrase = ""
    @State private var auditEvents: [NexusScriptAudit.Event] = []
    @State private var heroVisible = false
    private var workspace: UUID { NexusWorkspaceIdentity.id(for: "sandbox") }

    private struct PreviewItem: Identifiable {
        let id = UUID()
        let path: String
        let data: Data
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .frame(minHeight: 520)
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 18) {
                    actionRow
                    if showControls { controlsPanel }
                    filesPanel
                    if !auditEvents.isEmpty { auditPanel }
                    Text("沙箱页属 sandbox 工作区；对话属 chat 工作区。http_fetch 仅 HTTPS；预览禁脚本；宿主密钥不进沙箱。")
                        .font(.caption).foregroundStyle(Color.bgTextSecondary)
                }
                .padding(20)
            }
        }
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.035, green: 0.07, blue: 0.05), Color.bgDark, Color(red: 0.02, green: 0.05, blue: 0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                BGAuraOrb(diameter: 320)
                    .opacity(0.9)
                    .offset(x: 110, y: -40)
                    .blur(radius: reduceMotion ? 0 : 0.2)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { heroVisible = true }
            refreshFiles()
            auditEvents = NexusScriptAudit.recentEvents()
        }
        .onChange(of: allowExecution) { _, enabled in
            if !enabled { NexusLinuxRuntime.shared.cancelActive(reason: "内置执行已关闭") }
        }
        .sheet(isPresented: $showTerminal) {
            NavigationStack {
                NexusTerminalView(workspaceName: "sandbox").navigationTitle("沙箱终端")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showTerminal = false } } }
            }
        }
        .sheet(isPresented: $showStorage) { NexusStorageView() }
        .sheet(item: $previewItem) { item in
            NexusWorkspacePreview(path: item.path, data: item.data)
        }
        .fileImporter(isPresented: $importPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importFile(url)
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
        .alert("清空沙箱工作区", isPresented: $confirmClear) {
            TextField("输入「确认清空工作区」", text: $clearPhrase)
            Button("清空", role: .destructive) { clearWorkspace() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将删除沙箱工作区内可见文件，不可撤销。不影响聊天记录与长期记忆。")
        }
        .alert("沙箱提示", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { if !$0 { exportURL = nil } }
        )) {
            if let exportURL {
                NavigationStack {
                    VStack(spacing: 16) {
                        Text("文件已准备好，可分享或保存到文件 App。")
                            .font(.subheadline).foregroundStyle(Color.bgTextSecondary)
                        ShareLink(item: exportURL) {
                            Label("分享文件", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(BGSecondaryButtonStyle())
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgDark)
                    .navigationTitle("导出")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { self.exportURL = nil } } }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text("BLACK GOD")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundStyle(Color.bgJadeHi)
                .opacity(heroVisible ? 1 : 0)
                .offset(y: heroVisible ? 0 : 12)
                .accessibilityIdentifier("sandbox.brand")
            Text("沙箱")
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.bgTextPrimary)
                .padding(.top, 10)
                .opacity(heroVisible ? 1 : 0)
                .offset(y: heroVisible ? 0 : 18)
                .accessibilityIdentifier("sandbox.title")
                .accessibilityAddTraits(.isHeader)
            Text("本机 Linux 真跑起来。一键点亮，看见内核与玉绿现场。")
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(Color.bgTextSecondary)
                .padding(.top, 14)
                .frame(maxWidth: 320, alignment: .leading)
                .opacity(heroVisible ? 1 : 0)
                .offset(y: heroVisible ? 0 : 16)
            Button {
                runDemo()
            } label: {
                Label(busy ? "点亮中…" : "一键点亮", systemImage: busy ? "bolt.horizontal.fill" : "bolt.fill")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(BGPrimaryButtonStyle())
            .disabled(busy || !allowExecution)
            .padding(.top, 28)
            .opacity(heroVisible ? 1 : 0)
            .accessibilityIdentifier("sandbox.demo")
            Text(demoPhase.isEmpty ? status : demoPhase)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.bgJadeHi)
                .padding(.top, 14)
                .accessibilityIdentifier("sandbox.status")
            Text(quotaText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.bgTextSecondary)
                .padding(.top, 4)
                .accessibilityIdentifier("sandbox.quota")
            Spacer(minLength: 28)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { showTerminal = true } label: {
                Label("终端", systemImage: "terminal").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(BGSecondaryButtonStyle())
            .accessibilityIdentifier("sandbox.terminal")
            Button { showStorage = true } label: {
                Label("容量", systemImage: "internaldrive").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(BGSecondaryButtonStyle())
            .accessibilityIdentifier("sandbox.storage")
            Button { withAnimation { showControls.toggle() } } label: {
                Label(showControls ? "收起" : "开关", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(BGSecondaryButtonStyle())
            .accessibilityIdentifier("sandbox.controls")
        }
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("允许助手使用沙箱执行", isOn: $allowExecution)
                .font(.headline).tint(Color.bgJadeHi)
                .accessibilityIdentifier("execution.enabled")
            Toggle("允许沙箱 HTTPS 抓取", isOn: $allowNetwork)
                .font(.headline).tint(Color.bgJadeHi)
                .accessibilityIdentifier("sandbox.network")
            Toggle("允许危险命令（仍留审计痕迹）", isOn: $allowDangerous)
                .font(.headline).tint(Color.bgJadeHi)
                .accessibilityIdentifier("sandbox.allowDangerous")
            Text(imageQuotaText)
                .font(.caption.monospacedDigit()).foregroundStyle(Color.bgJadeHi)
                .accessibilityIdentifier("sandbox.imageQuota")
            Text("工作区硬上限 \(NexusWorkspaceQuota.maxFiles) 文件 / \(NexusWorkspaceQuota.byteText(NexusWorkspaceQuota.maxBytes))；整镜像硬顶 \(NexusStorage.absoluteCeilingGiB) GiB。")
                .font(.footnote).foregroundStyle(Color.bgTextSecondary)
        }
        .padding(16).bgFloating()
    }

    private var filesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("工作区文件").font(.headline).foregroundStyle(Color.bgTextPrimary)
                Spacer()
                Button("刷新") { refreshFiles() }
                    .disabled(busy)
                    .accessibilityIdentifier("sandbox.refresh")
            }
            if files.isEmpty {
                Text(busy ? "正在读取…" : "还没有文件。点「一键点亮」，或导入 / 让对话生成。")
                    .font(.footnote).foregroundStyle(Color.bgTextSecondary)
            } else {
                ForEach(files) { file in
                    HStack {
                        Image(systemName: "doc").foregroundStyle(Color.bgJadeHi)
                        Text(file.path).font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.bgTextPrimary).lineLimit(2)
                        Spacer()
                        Button("预览") { previewFile(file.path) }
                            .disabled(busy)
                            .accessibilityIdentifier("sandbox.preview.\(file.path)")
                        Button("导出") { exportFile(file.path) }
                            .disabled(busy)
                            .accessibilityIdentifier("sandbox.export.\(file.path)")
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack(spacing: 10) {
                Button { importPicker = true } label: {
                    Label("导入文件", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(BGSecondaryButtonStyle())
                .disabled(busy)
                .accessibilityIdentifier("sandbox.import")
                Button(role: .destructive) { confirmClear = true; clearPhrase = "" } label: {
                    Label("清空工作区", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(BGSecondaryButtonStyle())
                .disabled(busy || files.isEmpty)
                .accessibilityIdentifier("sandbox.clear")
            }
        }
        .padding(16).bgFloating()
    }

    private var auditPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近审计").font(.headline).foregroundStyle(Color.bgTextPrimary)
            ForEach(auditEvents.prefix(5)) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(auditTitle(event))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(event.level == .block && !event.overridden ? Color.red : Color.bgJadeHi)
                    Text(event.preview)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.bgTextSecondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16).bgFloating()
        .accessibilityIdentifier("sandbox.audit")
    }

    private func runDemo() {
        guard !busy else { return }
        busy = true
        demoPhase = "准备点亮…"
        Task {
            do {
                let outcome = try await NexusSandboxDemo.run(workspace: workspace) { phase in
                    Task { @MainActor in demoPhase = phase }
                }
                previewItem = PreviewItem(path: outcome.path, data: outcome.data)
                status = "已点亮 · 内核探测完成"
                demoPhase = "展示页已打开"
                busy = false
                refreshFiles()
            } catch {
                busy = false
                errorText = error.localizedDescription
                demoPhase = "点亮失败"
            }
        }
    }

    private func refreshFiles() {
        guard !busy else { return }
        busy = true
        status = "正在读取工作区…"
        Task {
            defer { busy = false }
            do {
                let listed = try await NexusLinuxRuntime.shared.listWorkspaceFiles(workspace: workspace)
                files = listed
                let host = await MainActor.run { NexusLinuxRuntime.shared.hostWorkspaceURL(for: workspace) }
                let quota = try NexusWorkspaceQuota.measure(at: host)
                quotaText = quota.summary
                imageQuotaText = await NexusLinuxRuntime.shared.imageQuotaSummary()
                auditEvents = NexusScriptAudit.recentEvents()
                status = listed.isEmpty ? "本机 Alpine · 工作区为空" : "本机 Alpine · \(listed.count) 个文件"
                errorText = nil
            } catch {
                files = []
                status = "沙箱未就绪"
                quotaText = "配额未读取"
                imageQuotaText = "整镜像：未读取"
                auditEvents = NexusScriptAudit.recentEvents()
                errorText = error.localizedDescription
            }
        }
    }

    private func auditTitle(_ event: NexusScriptAudit.Event) -> String {
        let level: String
        switch event.level {
        case .block: level = event.overridden ? "高危已放行" : "已拦截"
        case .caution: level = "提醒"
        case .allow: level = "放行"
        }
        let reason = event.reasons.first ?? ""
        return reason.isEmpty ? level : "\(level) · \(reason)"
    }

    private func importFile(_ url: URL) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                try await NexusLinuxRuntime.shared.importToWorkspace(data: data, named: url.lastPathComponent, workspace: workspace)
                refreshFiles()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func exportFile(_ path: String) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let data = try await NexusLinuxRuntime.shared.exportWorkspaceFile(path, workspace: workspace)
                let name = NexusWorkspacePath.sanitizeFileName(path)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                exportURL = url
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func previewFile(_ path: String) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let data = try await NexusLinuxRuntime.shared.exportWorkspaceFile(path, workspace: workspace)
                previewItem = PreviewItem(path: path, data: data)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func clearWorkspace() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await NexusLinuxRuntime.shared.clearWorkspaceFiles(workspace: workspace, confirm: clearPhrase)
                confirmClear = false
                refreshFiles()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
