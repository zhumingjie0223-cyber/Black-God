import SwiftUI
import UniformTypeIdentifiers

/// 沙箱主页：内置 Alpine Linux 工作区、终端、文件与空间，不再藏进高级设置。
struct NexusSandboxView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("blackgod.linux.modelTools") private var allowExecution = true
    @State private var showTerminal = false
    @State private var showStorage = false
    @State private var files: [NexusWorkspaceFile] = []
    @State private var status = "尚未读取工作区"
    @State private var busy = false
    @State private var errorText: String?
    @State private var importPicker = false
    @State private var exportURL: URL?
    @State private var confirmClear = false
    @State private var clearPhrase = ""
    private var workspace: UUID { NexusWorkspaceIdentity.id(for: "sandbox") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("沙箱").font(.title2.weight(.semibold)).foregroundStyle(Color.bgTextPrimary)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("sandbox.title")
                        Text("本机 Alpine Linux · 独立工作区")
                            .font(.caption).foregroundStyle(Color.bgTextSecondary)
                    }
                    Spacer(minLength: 0)
                    Circle()
                        .fill(allowExecution ? Color.bgJadeHi : Color.bgTextSecondary.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(allowExecution ? "执行已开启" : "执行已关闭")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("允许助手使用沙箱执行", isOn: $allowExecution)
                        .font(.headline).tint(Color.bgJadeHi)
                        .accessibilityIdentifier("execution.enabled")
                    Text("开启后，对话与快捷指令可在隔离工作区运行命令、读写文件。进入后台会停止当前命令。")
                        .font(.footnote).foregroundStyle(Color.bgTextSecondary)
                    Text(status).font(.caption).foregroundStyle(Color.bgTextSecondary)
                        .accessibilityIdentifier("sandbox.status")
                }
                .padding(16).bgFloating()

                HStack(spacing: 10) {
                    Button { showTerminal = true } label: {
                        Label("打开终端", systemImage: "terminal").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(BGPrimaryButtonStyle())
                    .accessibilityIdentifier("sandbox.terminal")
                    Button { showStorage = true } label: {
                        Label("容量", systemImage: "internaldrive").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(BGSecondaryButtonStyle())
                    .accessibilityIdentifier("sandbox.storage")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("工作区文件").font(.headline).foregroundStyle(Color.bgTextPrimary)
                        Spacer()
                        Button("刷新") { refreshFiles() }
                            .disabled(busy)
                            .accessibilityIdentifier("sandbox.refresh")
                    }
                    if files.isEmpty {
                        Text(busy ? "正在读取…" : "工作区暂无文件。可导入，或让对话在沙箱里生成。")
                            .font(.footnote).foregroundStyle(Color.bgTextSecondary)
                    } else {
                        ForEach(files) { file in
                            HStack {
                                Image(systemName: "doc").foregroundStyle(Color.bgJadeHi)
                                Text(file.path).font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(Color.bgTextPrimary).lineLimit(2)
                                Spacer()
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

                Text("沙箱与聊天会话隔离：这里的文件属于沙箱工作区；对话任务使用独立聊天工作区。密钥与宿主相册不会挂进沙箱。")
                    .font(.caption).foregroundStyle(Color.bgTextSecondary)
            }
            .padding(20)
        }
        .background(Color.bgDark)
        .onAppear { refreshFiles() }
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

    private func refreshFiles() {
        guard !busy else { return }
        busy = true
        status = "正在准备沙箱…"
        Task {
            defer { busy = false }
            do {
                let listed = try await NexusLinuxRuntime.shared.listWorkspaceFiles(workspace: workspace)
                files = listed
                status = listed.isEmpty ? "沙箱就绪 · 工作区为空" : "沙箱就绪 · \(listed.count) 个文件"
                errorText = nil
            } catch {
                files = []
                status = "沙箱未就绪"
                errorText = error.localizedDescription
            }
        }
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
                let name = NexusLinuxRuntime.sanitizeFileName(path)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                exportURL = url
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
