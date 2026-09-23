import SwiftUI

/// Secondary controls live under My settings; everyday work starts in chat.
struct NexusAdvancedSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("blackgod.linux.modelTools") private var allowExecution = true
    @State private var showTerminal = false
    @State private var showStorage = false
    @State private var showShuyu = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("允许助手执行任务", isOn: $allowExecution)
                            .font(.headline).tint(Color.bgJadeHi)
                            .accessibilityIdentifier("execution.enabled")
                        Text("允许 Black God 在应用内的独立工作区操作文件和访问网络。日常任务可直接在对话中提出。")
                            .font(.footnote).foregroundStyle(Color.bgTextSecondary)
                    }.bgCard()
                    VStack(spacing: 0) {
                        Button { showStorage = true } label: {
                            SettingRow(icon: "internaldrive", title: "容量与空间", value: "查看用量，调整工作区预算", color: .bgJadeHi)
                        }.accessibilityIdentifier("storage.open")
                        Divider().overlay(Color.bgBorder)
                        Button { showShuyu = true } label: {
                            SettingRow(icon: "character.book.closed", title: "枢语", value: "语言检索与组合", color: .bgJadeHi)
                        }.accessibilityIdentifier("shuyu.open")
                        Divider().overlay(Color.bgBorder)
                        Button { showTerminal = true } label: {
                            SettingRow(icon: "terminal", title: "手动终端", value: "高级调试 · 内置 Linux 环境", color: .bgJadeHi)
                        }.accessibilityIdentifier("linux.advanced")
                    }.buttonStyle(.plain).bgCard()
                    Text("进入后台会停止当前命令。手动终端用于高级调试。")
                        .font(.caption).foregroundStyle(Color.bgTextSecondary)
                }.padding(20)
            }
            .background(Color.bgDark)
            .navigationTitle("高级设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showStorage) { NexusStorageView() }
            .sheet(isPresented: $showShuyu) { NexusShuyuView() }
            .sheet(isPresented: $showTerminal) {
                NavigationStack {
                    NexusTerminalView().navigationTitle("手动终端")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showTerminal = false } } }
                }
            }
        }
    }
}

private struct NexusToolsSectionLabel: View {
    let title: String
    let detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline).foregroundStyle(Color.bgTextPrimary)
            if let detail { Text(detail).font(.caption).foregroundStyle(Color.bgTextSecondary) }
        }
    }
}

/// Advanced diagnostic terminal; ordinary tasks enter through the shared chat engine.
struct NexusTerminalView: View {
    @StateObject private var live = NexusLiveExecution()
    @FocusState private var editingCommand: Bool
    @State private var command = "uname -a\nprintf 'Hello from Black God\\n'"
    @State private var result = ""
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var records: [NexusExecutionRecord] = []
    @State private var journalError: String?
    private var workspace: UUID { NexusWorkspaceIdentity.id(for: "tools") }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    BGPageHeader(title: "命令工作区", subtitle: "本机 Alpine Linux · ARM64", eyebrow: "高级工具 · 实验功能")
                    VStack(alignment: .leading, spacing: 14) {
                        Label("编写命令", systemImage: "terminal").font(.headline).foregroundStyle(Color.bgTextPrimary)
                        TextEditor(text: $command)
                            .focused($editingCommand)
                            .font(.system(.body, design: .monospaced)).foregroundStyle(Color.bgTextPrimary)
                            .frame(minHeight: 170).scrollContentBackground(.hidden).padding(12)
                            .background(Color.bgDark, in: RoundedRectangle(cornerRadius: 14))
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityLabel("Linux 命令").accessibilityIdentifier("linux.command")
                            .disabled(running)
                        Button(action: runCommand) {
                            Label(running ? "停止命令" : "运行命令", systemImage: running ? "stop.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(BGPrimaryButtonStyle()).accessibilityIdentifier("linux.run")
                        HStack(spacing: 10) {
                            Button { command = "" } label: {
                                Label("清空命令", systemImage: "delete.left").frame(maxWidth: .infinity)
                            }.buttonStyle(BGSecondaryButtonStyle()).disabled(running).accessibilityIdentifier("linux.clear")
                            if !result.isEmpty && !running {
                                ShareLink(item: result) {
                                    Label("分享输出", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                                }.buttonStyle(BGSecondaryButtonStyle())
                            }
                        }
                    }.bgCard().id("terminal.editor")
                    if !result.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("运行输出", systemImage: "text.alignleft").font(.headline).foregroundStyle(Color.bgTextPrimary)
                            if !running {
                                Button {
                                    withAnimation { proxy.scrollTo("terminal.editor", anchor: .top) }
                                } label: {
                                    Label("回到命令", systemImage: "arrow.up").frame(maxWidth: .infinity)
                                }.buttonStyle(BGSecondaryButtonStyle()).accessibilityIdentifier("linux.backToCommand")
                            }
                            Text(result).accessibilityIdentifier("linux.result")
                                .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                                .foregroundStyle(Color.bgTextPrimary).frame(maxWidth: .infinity, alignment: .leading)
                        }.bgCard().id("terminal.output")
                    }
                    NexusLiveExecutionView(live: live) { task?.cancel() }.id("terminal.live")
                    if let journalError {
                        Label(journalError, systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(Color.red).frame(maxWidth: .infinity, alignment: .leading).bgCard()
                    }
                    if !records.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            NexusToolsSectionLabel(title: "最近执行", detail: "仅保存时间和结果状态，不保存命令正文。")
                            ForEach(records.prefix(5)) { record in
                                HStack(spacing: 10) {
                                    Image(systemName: record.status == "completed" ? "checkmark.circle" : record.status == "failed" ? "exclamationmark.circle" : "clock")
                                        .foregroundStyle(record.status == "completed" ? Color.bgJadeHi : Color.bgTextSecondary)
                                    Text(record.startedAt, style: .time).foregroundStyle(Color.bgTextSecondary)
                                    Spacer(minLength: 4)
                                    Text(statusName(record.status)).foregroundStyle(Color.bgTextPrimary)
                                        .accessibilityIdentifier(record.id == records.first?.id ? "linux.latestStatus" : "linux.status.\(record.id)")
                                    if let code = record.exitCode { Text("退出码 \(code)").foregroundStyle(Color.bgTextSecondary) }
                                }.font(.caption).padding(.vertical, 5)
                            }
                            Text("中断的命令不会自动重跑。")
                                .font(.caption).foregroundStyle(Color.bgTextSecondary)
                        }.bgCard()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("运行范围", systemImage: "info.circle").font(.subheadline.weight(.semibold))
                        Text("内置 BusyBox，可运行 sh、awk 等脚本。命令默认最多 30 秒，单路输出上限 256 KiB。")
                        Text("进入后台会停止当前命令，暂不支持持续后台任务。")
                    }.font(.caption).foregroundStyle(Color.bgTextSecondary).bgCard()
                    Text("运行环境由 Black God 内置提供。所含开源组件、源码与许可证见「开源许可」页。")
                        .font(.caption).foregroundStyle(Color.bgTextSecondary)
                }.padding(20)
            }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: running) { _, isRunning in
                    guard isRunning || !result.isEmpty else { return }
                    withAnimation { proxy.scrollTo(isRunning ? "terminal.live" : "terminal.output", anchor: .top) }
                }
                .onAppear { refreshJournal() }
                .onDisappear { task?.cancel() }
        }
    }
    private func runCommand() {
        if running { task?.cancel(); return }
        editingCommand = false
        running = true
        result = "正在执行…"
        let script = command
        live.begin(goal: "手动终端")
        live.phase("正在准备运行环境…")
        live.append(.command, script)
        task = Task {
            defer { running = false; task = nil; refreshJournal() }
            do {
                let output = try await NexusLinuxRuntime.shared.execute(command: script, workspace: workspace,
                    onStatus: { live.phase($0) }, onOutput: { line, error in live.append(error ? .error : .output, line) })
                result = "退出码：\(output.exitCode) · \(String(format: "%.2f", output.duration)) 秒\n"
                    + output.output + (output.errorOutput.isEmpty ? "" : "\n错误输出：\n" + output.errorOutput)
                    + (output.failure.map { "\n" + $0 } ?? "")
                live.append(output.succeeded ? .result : .error, result)
                live.finish(output.succeeded ? .answered : .failed, message: output.succeeded ? "命令执行结束" : "命令未成功完成")
            } catch is CancellationError { result = "命令已取消，子进程已终止。"; live.finish(.cancelled, message: result) }
            catch { result = error.localizedDescription; live.finish(.failed, message: result) }
        }
    }
    private func refreshJournal() {
        do {
            try NexusLinuxRuntime.shared.prepare()
            records = try NexusLinuxRuntime.shared.recentExecutions().filter { $0.workspace == workspace }.reversed()
            journalError = nil
        } catch { journalError = "无法读取执行记录：" + error.localizedDescription }
    }
    private func statusName(_ status: String) -> String {
        ["running": "执行中", "completed": "完成", "failed": "失败", "cancelled": "已取消", "interrupted": "意外中断"][status] ?? status
    }

}
