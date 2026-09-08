import SwiftUI

/// Users describe the result; the agent generates commands inside the embedded runtime.
struct ToolsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var chat: ChatViewModel
    @AppStorage("blackgod.linux.modelTools") private var allowExecution = true
    @State private var request = ""
    @State private var showTerminal = false
    @State private var showStorage = false
    @State private var showShuyu = false
    @State private var showConnection = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("内置执行").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                Text("说出目标，Black God 帮你执行")
                    .font(.headline).foregroundStyle(Color.bgTextPrimary)
                Text("无需安装其他应用，也不用输入代码。你提出需求，AI 会按需使用内置工具计算、处理文字和生成工作区文件，并根据实际执行结果回答。")
                    .font(.subheadline).foregroundStyle(Color.bgTextSecondary)
                Toggle("允许 Black God 执行任务", isOn: $allowExecution)
                    .accessibilityIdentifier("execution.enabled")
                Text("执行范围是应用内的独立工作区，可以修改其中的文件和访问网络，不能直接读取手机其他应用。进入后台会停止当前命令。")
                    .font(.caption).foregroundStyle(Color.bgTextSecondary)
                TextField("例如：统计这段文字的字数并找出重复词……", text: $request, axis: .vertical)
                    .lineLimit(3...6).padding(12).bgCard()
                    .accessibilityIdentifier("execution.request")
                Button(chat.isTyping ? "查看正在进行的任务" : "交给 Black God") {
                    if chat.isTyping { appState.currentTab = .chat; return }
                    guard chat.apiKeyConfigured else { showConnection = true; return }
                    chat.send(request)
                    if chat.isTyping { appState.currentTab = .chat }
                }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("execution.start")
                .disabled(!chat.isTyping && request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !allowExecution {
                    Text("内置执行已关闭；仍可对话和计算，需要操作文件的任务会受限。")
                        .font(.caption).foregroundStyle(Color.bgTextSecondary)
                }
                Text("可以这样说").font(.headline)
                ForEach(["计算12个月每月存500元的累计金额，并核对结果。", "把苹果12元、牛奶18元、面包9元整理成CSV文件保存在工作区，并核对总价。", "统计这段文字里每个词出现的次数：apple banana apple orange banana apple"], id: \.self) { example in
                    Button(example) { request = example }
                        .font(.subheadline).foregroundStyle(Color.bgTextPrimary).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12).bgCard()
                }
                Button("枢语：自己的语言") { showShuyu = true }.accessibilityIdentifier("shuyu.open")
                Button("查看容量与扩展空间") { showStorage = true }.accessibilityIdentifier("storage.open")
                Divider()
                Button("高级工具：手动终端") { showTerminal = true }
                    .font(.caption).accessibilityIdentifier("linux.advanced")
                Text("内置运行能力仍在验收中。手动终端仅供调试，日常使用直接对话即可。")
                    .font(.caption).foregroundStyle(Color.bgTextSecondary)
            }.padding(16).padding(.bottom, 40)
        }.padding(.top, 50)
        .sheet(isPresented: $showTerminal) {
            NavigationStack {
                NexusTerminalView().navigationTitle("手动终端")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showTerminal = false } } }
            }
        }
        .sheet(isPresented: $showShuyu) { NexusShuyuView() }
        .sheet(isPresented: $showStorage) { NexusStorageView() }
        .sheet(isPresented: $showConnection) { APIConfigView() }
        .onChange(of: allowExecution) { _, enabled in
            if !enabled {
                NexusLinuxRuntime.shared.cancelActive(reason: "内置执行已关闭")
                if chat.isTyping { chat.cancel() }
            }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Linux 工作区").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                Text("本机 Alpine Linux · ARM64 · 实验功能")
                    .font(.subheadline).foregroundStyle(Color.bgTextSecondary)
                NexusLiveExecutionView(live: live) { task?.cancel() }
                TextEditor(text: $command)
                    .focused($editingCommand)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 135).scrollContentBackground(.hidden).bgCard()
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityLabel("Linux 命令").accessibilityIdentifier("linux.command")
                    .disabled(running)
                HStack {
                    Button(running ? "停止命令" : "运行命令") {
                        if running { task?.cancel(); return }
                        editingCommand = false
                        running = true
                        result = "正在执行…"
                        let script = command
                        live.begin(goal: "手动终端")
                        live.phase("正在执行命令")
                        live.append(.command, script)
                        task = Task {
                            defer { running = false; task = nil; refreshJournal() }
                            do {
                                let output = try await NexusLinuxRuntime.shared.execute(command: script, workspace: workspace, onOutput: { line, error in live.append(error ? .error : .output, line) })
                                result = "退出码：\(output.exitCode) · \(String(format: "%.2f", output.duration)) 秒\n"
                                    + output.output + (output.errorOutput.isEmpty ? "" : "\n错误输出：\n" + output.errorOutput)
                                    + (output.failure.map { "\n" + $0 } ?? "")
                                live.append(output.succeeded ? .result : .error, result)
                                live.finish(output.succeeded ? .answered : .failed, message: output.succeeded ? "命令执行结束" : "命令未成功完成")
                            } catch is CancellationError { result = "命令已取消，子进程已终止。"; live.finish(.cancelled, message: result) }
                            catch { result = error.localizedDescription; live.finish(.failed, message: result) }
                        }
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("linux.run")
                    Button("清空命令") { command = "" }.disabled(running).accessibilityIdentifier("linux.clear")
                    if !result.isEmpty && !running { ShareLink("分享输出", item: result) }
                }
                Text("内置 BusyBox 工具，可运行 sh、awk 等脚本。命令默认最多30秒，单路输出上限256 KiB。离开应用进入后台会停止当前命令；暂不支持持续后台任务。")
                    .font(.footnote).foregroundStyle(Color.bgTextSecondary)
                if !result.isEmpty {
                    Text(result).accessibilityIdentifier("linux.result").font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding().bgCard()
                }
                if let journalError { Text(journalError).font(.footnote).foregroundStyle(.red) }
                if !records.isEmpty {
                    Text("最近执行").font(.headline)
                    Text("仅保留时间和结果状态，不保存命令正文。中断的命令不会自动重跑。")
                        .font(.footnote).foregroundStyle(Color.bgTextSecondary)
                    ForEach(records.prefix(5)) { record in
                        HStack {
                            Text(record.startedAt, style: .time)
                            Spacer()
                            Text(statusName(record.status))
                            if let code = record.exitCode { Text("退出码 \(code)") }
                        }.font(.caption)
                    }
                }
                Text("运行环境来源：iSH / OpenMinis（GPLv3）与 Alpine Linux。源码与许可证见项目 THIRD_PARTY.md。")
                    .font(.caption).foregroundStyle(Color.bgTextSecondary)
            }.padding(16).padding(.bottom, 100)
        }
            .onAppear { refreshJournal() }
            .onDisappear { task?.cancel() }
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
