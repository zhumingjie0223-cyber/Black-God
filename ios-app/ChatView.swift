import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vm: ChatViewModel
    @State private var showConfig = false
    @State private var showProgress = false
    @State private var showClear = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image("BrandMark").resizable().scaledToFit()
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("神枢").font(.bgHeadline()).foregroundStyle(Color.bgTextPrimary)
                    Text(vm.currentMood).font(.caption).foregroundStyle(Color.bgGoldLight)
                }
                Spacer()
                Button { showClear = true } label: { Image(systemName: "square.and.pencil").font(.title3) }
                    .accessibilityLabel("新对话").disabled(vm.isTyping)
                Button { showConfig = true } label: { Image(systemName: "slider.horizontal.3").font(.title3) }
                    .accessibilityLabel("API 配置")
            }.padding(.horizontal, 20).padding(.vertical, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if vm.messages.count == 1 {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("把想法，变成结果。")
                                    .font(.system(size: 28, weight: .semibold)).foregroundStyle(Color.bgTextPrimary)
                                Text("任务规划 · 本机工具 · 由你掌控")
                                    .font(.subheadline).foregroundStyle(Color.bgTextSecondary)
                            }.padding(.vertical, 22)
                        }
                        ForEach(vm.messages) { message in
                            MessageBubble(message: message, memory: vm.memory).id(message.id)
                        }
                        if let checkpoint = vm.pendingCheckpoint, !vm.isTyping {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("有一个未完成的任务", systemImage: "arrow.clockwise")
                                Text(checkpoint.plan.goal).font(.caption).lineLimit(3)
                                HStack {
                                    Button("继续任务") { vm.canSend ? vm.resume() : (showConfig = true) }
                                    Spacer()
                                    Button("移除检查点", role: .destructive) { vm.discardCheckpoint() }
                                }.font(.subheadline)
                            }.padding(16).bgCard()
                        }
                        if let error = vm.lastError { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(.horizontal, 20).padding(.bottom, 16)
                }
                .onChange(of: vm.messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .scrollDismissesKeyboard(.interactively)
            }
            if vm.currentPlan != nil || vm.isTyping {
                HStack(spacing: 10) {
                    if vm.isTyping { ProgressView().tint(Color.bgGoldLight) }
                    Button { showProgress = true } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(vm.statusHint ?? "查看任务过程").lineLimit(1)
                            if let plan = vm.currentPlan { Text("\(plan.steps.filter { $0.status == .passed }.count) / \(plan.steps.count) 步 · \(vm.toolTraces.count) 次工具调用").font(.caption2) }
                        }.font(.caption).foregroundStyle(Color.bgTextSecondary)
                    }
                    Spacer(minLength: 4)
                    if vm.isTyping { Button("停止", role: .cancel) { vm.cancel() }.font(.subheadline) }
                    else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.bgTextSecondary) }
                }.padding(.horizontal, 20).padding(.vertical, 10).background(Color.bgCard)
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("说说你想完成的事…", text: $vm.draft, axis: .vertical)
                    .focused($inputFocused).lineLimit(1...5).font(.bgBody())
                    .padding(.horizontal, 15).padding(.vertical, 12)
                    .background(Color.bgCardLight, in: RoundedRectangle(cornerRadius: 19))
                Button {
                    guard vm.canSend else { showConfig = true; return }
                    let text = vm.draft
                    vm.send(text)
                    if vm.isTyping { vm.draft = ""; inputFocused = false }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 38)) }
                    .accessibilityLabel("发送任务")
                    .disabled(vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isTyping)
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .confirmationDialog("清空当前对话并开始新对话？", isPresented: $showClear, titleVisibility: .visible) {
            Button("开始新对话") { vm.clearConversation() }
            Button("取消", role: .cancel) {}
        } message: { Text("当前对话将不再发送给模型；已收藏的记忆和任务记录会保留。") }
        .sheet(isPresented: $showConfig) { APIConfigView().environmentObject(appState) }
        .sheet(isPresented: $showProgress) { NexusTaskProgressView().environmentObject(vm) }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    @ObservedObject var memory: NexusMemoryStore
    @State private var saved = false
    @State private var showSaveError = false
    var isUser: Bool { message.role == "user" }
    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 9) {
                Text(message.content).font(.bgBody()).textSelection(.enabled)
                    .foregroundStyle(isUser ? Color.bgTextPrimary : Color.bgTextPrimary)
                if !isUser {
                    HStack(spacing: 18) {
                        ShareLink(item: message.content) { Label("分享", systemImage: "square.and.arrow.up") }
                        Button {
                            saved = memory.remember(message.content, kind: "saved", source: "user", confidence: 1)
                            showSaveError = !saved
                        } label: { Label(saved ? (message.content.count > 4000 ? "已收藏摘录" : "已收藏") : (message.content.count > 4000 ? "收藏前4000字" : "记住"), systemImage: saved ? "bookmark.fill" : "bookmark") }
                            .disabled(saved)
                    }.font(.caption2).foregroundStyle(Color.bgGoldLight)
                }
            }
            .padding(15).background(isUser ? Color.bgCardLight : Color.bgCard, in: RoundedRectangle(cornerRadius: 18))
            if !isUser { Spacer(minLength: 8) }
        }.alert("未能收藏", isPresented: $showSaveError) { Button("好", role: .cancel) {} } message: {
            Text(memory.lastError ?? "请稍后再试。")
        }
    }
}

struct NexusTaskProgressView: View {
    @EnvironmentObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let plan = vm.currentPlan {
                    Section("任务") { Text(plan.goal) }
                    Section("执行步骤") {
                        ForEach(plan.steps) { step in
                            DisclosureGroup {
                                if !step.instruction.isEmpty { Text(step.instruction) }
                                ForEach(step.acceptanceCriteria, id: \.self) { Text("· \($0)").font(.caption) }
                                if let result = step.result { Text(result).font(.caption).textSelection(.enabled) }
                            } label: {
                                Label(step.title, systemImage: step.status.symbol)
                                    .foregroundStyle(step.status == .failed ? Color.orange : Color.bgTextPrimary)
                            }
                        }
                    }
                }
                Section("工具记录 · \(vm.toolTraces.count)") {
                    ForEach(Array(vm.toolTraces.enumerated()), id: \.offset) { _, trace in
                        DisclosureGroup("\(trace.call.name) · \(trace.succeeded ? "完成" : "失败")") {
                            Text(trace.call.arguments.keys.sorted().map { "\($0): \(trace.call.arguments[$0] ?? "")" }.joined(separator: "\n")).font(.caption)
                            Text(trace.result).font(.caption).textSelection(.enabled)
                        }
                    }
                    if vm.toolTraces.isEmpty { Text("尚未调用工具").foregroundStyle(.secondary) }
                }
                Section { Text("步骤完成表示流程与输出完整性检查通过，不等于事实正确。重要结论请核对。AI 调用由所选服务商计费。").font(.caption).foregroundStyle(.secondary) }
            }.scrollContentBackground(.hidden).background(Color.bgDark)
                .navigationTitle("任务过程").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

extension NexusStepStatus {
    var symbol: String {
        switch self {
        case .pending: return "circle"
        case .running: return "arrow.triangle.2.circlepath.circle"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        case .skipped, .interrupted: return "pause.circle"
        }
    }
}
