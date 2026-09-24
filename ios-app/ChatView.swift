//
//  ChatView.swift — Black God AI对话界面
//

import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var vm: ChatViewModel
    @State private var input = ""
    @State private var skillDraft: NexusSkillDraft?
    @State private var memoryMessage: ChatMessage?
    @State private var showConnection = false
    @State private var showClearConversation = false
    @State private var showTaskDetails = false
    @State private var showPracticeDetails = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            PresenceStrip(snapshot: vm.presence) { vm.actOnPresence() }
                .padding(.horizontal, 16).padding(.bottom, 8)
            NexusActivitySummary(chat: vm, practice: vm.practice) { openTaskDetails(practice: vm.practice.isRunning) }
                .padding(.horizontal, 16).padding(.bottom, 8)
            GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if vm.messages.isEmpty && vm.lastError == nil && !vm.canResume {
                            ChatEmptyState()
                                .frame(minHeight: max(260, viewport.size.height - 36))
                        }
                        ForEach(vm.messages) { msg in
                            MessageBubble(message: msg).id(msg.id).contextMenu {
                                Button("复制") { UIPasteboard.general.string = msg.content }
                                if msg.role == "user" {
                                    Button("保存为长期记忆") { memoryMessage = msg }
                                }
                                if msg.role == "assistant", vm.canRegenerate, vm.messages.last?.id == msg.id {
                                    Button("重新生成") { vm.regenerate() }
                                }
                            }
                        }
                        if vm.isTyping { TypingIndicator().id("typing") }
                        VStack(alignment: .leading, spacing: 12) { conversationStatus }
                            .frame(maxWidth: .infinity).id("chat.status")
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("chat.status", anchor: .bottom) }
                }
                .onChange(of: vm.lastError) { _, error in
                    if error != nil { withAnimation { proxy.scrollTo("chat.status", anchor: .bottom) } }
                }
                .onChange(of: vm.canResume) { _, resumable in
                    if resumable { withAnimation { proxy.scrollTo("chat.status", anchor: .bottom) } }
                }
                .onChange(of: vm.statusHint) { _, status in
                    if !vm.isTyping, status != nil { withAnimation { proxy.scrollTo("chat.status", anchor: .bottom) } }
                }
            }
            }
            inputBar
        }
        .padding(.top, 12)
        .onAppear {
            NexusShuyuEngine.shared.prepare()
            vm.awaken()
            vm.hear(input)
            vm.attend(inputFocused)
        }
        .onChange(of: input) { _, text in vm.hear(text) }
        .onChange(of: inputFocused) { _, on in vm.attend(on) }
        .onChange(of: vm.composerPrefill) { _, text in
            guard let text else { return }
            input = text
            vm.composerPrefill = nil
            inputFocused = true
        }
        .sheet(item: $skillDraft) { draft in NexusSkillEditor(store: vm.skills, draft: draft) }
        .sheet(item: $memoryMessage) { msg in NexusMemoryEditor(memory: vm.memory, initialText: msg.content) }
        .sheet(isPresented: $showConnection) { APIConfigView() }
        .sheet(isPresented: $showTaskDetails) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        if showPracticeDetails {
                            NexusLiveExecutionView(live: vm.practice.live, stop: vm.practice.stop)
                        } else {
                            if let plan = vm.currentPlan, !plan.steps.isEmpty { NexusPlanStrip(plan: plan) }
                            NexusLiveExecutionView(live: vm.live, stop: vm.cancel)
                        }
                    }.padding(20)
                }
                .background(Color.bgDark).navigationTitle(showPracticeDetails ? "演练记录" : "任务详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showTaskDetails = false } } }
            }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .confirmationDialog("清空当前对话？", isPresented: $showClearConversation, titleVisibility: .visible) {
            Button("清空对话与任务记录", role: .destructive) {
                if vm.clearConversation() { input = ""; inputFocused = false }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将停止当前回答，删除本机聊天消息和任务恢复记录，无法撤销。已保存的长期记忆、技能与自我状态记录需在各自页面管理。损坏文件会保留本地恢复副本。")
        }
    }

    @ViewBuilder
    private var conversationStatus: some View {
        if vm.canResume, let task = vm.taskCheckpoint {
            VStack(alignment: .leading, spacing: 10) {
                Label("任务已暂停", systemImage: "pause.circle")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.bgJadeHi)
                Text(task.goal).font(.subheadline).lineLimit(2)
                ViewThatFits(in: .horizontal) {
                    HStack { recoveryActions }
                    VStack(alignment: .leading) { recoveryActions }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).bgFloating(cornerRadius: 18)
        }
        if !vm.isTyping, let status = vm.statusHint {
            Label(status, systemImage: "info.circle")
                .font(.caption).foregroundStyle(vm.live.state == .warning ? Color.orange : Color.bgTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let error = vm.lastError {
            VStack(alignment: .leading, spacing: 10) {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if vm.canRetry { Button("重试") { vm.retry() }.buttonStyle(BGSecondaryButtonStyle()) }
                    if !vm.apiKeyConfigured {
                        Button("配置连接") { showConnection = true }
                            .buttonStyle(BGSecondaryButtonStyle()).accessibilityIdentifier("api.open")
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).bgFloating(cornerRadius: 18)
        }
    }

    @ViewBuilder
    private var recoveryActions: some View {
        Button("继续任务") { vm.resume() }.buttonStyle(BGSecondaryButtonStyle()).accessibilityIdentifier("chat.resume")
        Button("结束此任务", role: .destructive) { vm.discardRecovery() }
            .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("chat.discard")
    }

    var chatHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.bgJadeHi)
                .frame(width: 42, height: 42)
                .background(Color.bgJade.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Black God").font(.title3.weight(.semibold)).foregroundStyle(Color.bgTextPrimary)
                    .accessibilityIdentifier("chat.title")
                HStack(spacing: 5) {
                    PresenceDot(duration: vm.presence.breath)
                    Text(vm.presence.action == .practice || vm.presence.action == .pulse ? "就绪" : vm.currentMood).font(.caption).foregroundStyle(Color.bgTextSecondary)
                        .accessibilityIdentifier("chat.mood")
                }
            }
            Spacer(minLength: 4)
            Menu {
                if vm.live.visible || vm.currentPlan != nil {
                    Button("任务详情", systemImage: "list.bullet.rectangle") { openTaskDetails(practice: false) }
                        .accessibilityIdentifier("chat.taskDetailsMenu")
                }
                if vm.practice.live.visible {
                    Button("演练记录", systemImage: "checklist") { openTaskDetails(practice: true) }
                }
                if !vm.isTyping, let task = vm.taskCheckpoint, NexusSkillContent.candidate(from: task) != nil {
                    Button("保存本次流程", systemImage: "square.stack.3d.up") { skillDraft = NexusSkillDraft(source: task) }
                        .accessibilityIdentifier("skills.fromTask")
                }
                if vm.canRegenerate {
                    Button("重新生成上一则", systemImage: "arrow.clockwise") { vm.regenerate() }
                        .accessibilityIdentifier("chat.regenerate")
                }
                Button("清空当前对话", role: .destructive) { showClearConversation = true }
                    .disabled(!vm.canClearConversation)
                    .accessibilityIdentifier("chat.clear")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.bgTextSecondary).frame(width: 44, height: 44)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("对话管理").accessibilityIdentifier("chat.actions")
            Button { showConnection = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 19))
                    .foregroundStyle(Color.bgJadeHi).frame(width: 44, height: 44)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("模型连接设置").accessibilityIdentifier("chat.connection")
        }
        .padding(.horizontal, 20).padding(.bottom, 14)
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = false }
    }

    var inputBar: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChatComposerChip.all, id: \.title) { chip in
                        Button { input = chip.prompt; inputFocused = true } label: {
                            Label(chip.title, systemImage: chip.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.bgTextSecondary)
                                .padding(.horizontal, 13).frame(minHeight: 44)
                                .background(Color.bgCard.opacity(0.75), in: Capsule())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier(chip.accessibilityID)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("说出你的想法…", text: $input, axis: .vertical)
                    .focused($inputFocused).font(.body).foregroundStyle(Color.bgTextPrimary).lineLimit(1...5)
                    .padding(.leading, 16).padding(.vertical, 15)
                    .submitLabel(.send)
                    .accessibilityIdentifier("chat.input")
                    .onSubmit { sendCurrent() }
                Button { sendCurrent() } label: {
                    Image(systemName: vm.isTyping ? "stop.fill" : "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(vm.isTyping || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.bgDark : Color.bgTextSecondary)
                        .frame(width: 44, height: 44)
                        .background(vm.isTyping || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.bgJadeHi : Color.bgCardLight, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain).padding(6)
                .disabled(!vm.isTyping && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(vm.isTyping ? "停止回答" : "发送消息")
                .accessibilityIdentifier("chat.send")
            }
            .bgFloating(cornerRadius: 26)
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(inputFocused ? Color.bgJadeHi.opacity(0.65) : .clear, lineWidth: 1))
            .shadow(color: Color.bgJadeHi.opacity(inputFocused ? 0.16 : 0.04), radius: inputFocused ? 18 : 8)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        .background(Color.bgDark.opacity(0.98))
    }

    private func openTaskDetails(practice: Bool) {
        showPracticeDetails = practice
        showTaskDetails = true
    }

    private func sendCurrent() {
        if vm.isTyping { vm.cancel(); return }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appState.haptic(.medium)
        vm.send(input)
        if vm.isTyping { input = "" }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    @State private var showEvidence = false
    var isUser: Bool { message.role == "user" }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 44) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                Text(message.content).font(.body).lineSpacing(5).textSelection(.enabled)
                    .foregroundStyle(isUser ? Color.bgDark : Color.bgTextPrimary)
                    .padding(.horizontal, isUser ? 16 : 4).padding(.vertical, isUser ? 11 : 6)
                    .background(isUser ? AnyShapeStyle(LinearGradient.goldGradient) : AnyShapeStyle(Color.clear))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                if !isUser, let evidence = message.evidence, !evidence.isEmpty {
                    DisclosureGroup(isExpanded: $showEvidence) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                                Text(item).font(.caption).foregroundStyle(Color.bgTextSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(.top, 6)
                    } label: {
                        Label("查看依据", systemImage: "checkmark.shield")
                            .font(.caption).foregroundStyle(Color.bgTextSecondary)
                    }
                    .tint(Color.bgTextSecondary)
                    .accessibilityIdentifier("chat.evidence")
                }
            }
            if !isUser { Spacer(minLength: 20) }
        }
    }
}

// 仅自动化测试的调试构建停用装饰性循环动效，避免 XCTest 永远等不到界面空闲。
// 正式发行包与普通调试启动始终保留原有动效；不影响任何状态计时或任务执行。
private enum ChatMotion {
    static var continuousAnimationsEnabled: Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment["BLACKGOD_UI_TEST_NO_CONTINUOUS_ANIMATIONS"] != "1"
#else
        return true
#endif
    }
}

struct TypingIndicator: View {
    @State private var on = false
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(Color.bgJadeHi).frame(width: 7, height: 7)
                        .scaleEffect(on ? 1.18 : 0.86)
                        .opacity(on ? (i == 1 ? 1 : 0.58) : 0.28)
                        .animation(ChatMotion.continuousAnimationsEnabled ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(Double(i) * 0.12) : nil, value: on)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            Spacer()
        }
        .onAppear { on = true }
    }
}

struct ChatComposerChip {
    let title: String
    let prompt: String
    let accessibilityID: String
    var icon: String {
        switch title {
        case "计算": return "number"
        case "规划": return "list.bullet"
        case "枢语": return "character.book.closed"
        default: return "leaf"
        }
    }
    static let all = [
        ChatComposerChip(title: "计算", prompt: "帮我计算并核对结果：", accessibilityID: "chat.chip.calc"),
        ChatComposerChip(title: "规划", prompt: "把这件事拆成可检查的步骤：", accessibilityID: "chat.chip.plan"),
        ChatComposerChip(title: "枢语", prompt: "用枢语检索并造一个词：", accessibilityID: "chat.chip.shuyu"),
        ChatComposerChip(title: "一息", prompt: "用枢语一息看现在：", accessibilityID: "chat.chip.pulse")
    ]
}

struct PresenceDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let duration: Double
    @State private var on = false
    var body: some View {
        Circle().fill(Color.bgJadeHi).frame(width: 7, height: 7)
            .scaleEffect(on ? 1.28 : 0.92)
            .opacity(on ? 1 : 0.42)
            .accessibilityIdentifier("chat.breath")
            .onAppear { breathe(duration) }
            .onChange(of: duration) { _, value in breathe(value) }
    }
    private func breathe(_ value: Double) {
        guard !reduceMotion, ChatMotion.continuousAnimationsEnabled else { on = true; return }
        on = false
        withAnimation(.easeInOut(duration: max(0.6, value)).repeatForever(autoreverses: true)) { on = true }
    }
}

struct PresenceStrip: View {
    let snapshot: NexusPresenceSnapshot
    let act: () -> Void
    private var hasPendingAction: Bool { snapshot.action != .pulse && snapshot.action != .practice && snapshot.action != .none }
    var body: some View {
        HStack(spacing: 8) {
            if hasPendingAction {
                Text(snapshot.nextWork).font(.caption).foregroundStyle(Color.bgTextSecondary).lineLimit(1)
                Spacer(minLength: 8)
                Button(snapshot.actionTitle, action: act)
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.bgJadeHi)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("chat.act")
            }
        }
        .padding(.horizontal, hasPendingAction ? 12 : 0)
        .frame(maxWidth: .infinity, minHeight: hasPendingAction ? 44 : 0)
        .background(hasPendingAction ? Color.bgCard.opacity(0.5) : .clear, in: Capsule())
        .accessibilityElement(children: .contain).accessibilityIdentifier("chat.presence")
    }
}

struct ChatEmptyState: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        VStack(spacing: 24) {
            BGAuraOrb(diameter: sizeClass == .regular ? 320 : 250)
            Text("说出你的想法")
                .font(.title3.weight(.medium)).tracking(2)
                .foregroundStyle(Color.bgTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityIdentifier("chat.empty")
    }
}

struct NexusPlanStrip: View {
    let plan: NexusTaskPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前计划").font(.caption.bold()).foregroundStyle(Color.bgJadeHi)
            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 8) {
                    Circle().fill(color(step.status)).frame(width: 7, height: 7)
                    Text("\(index + 1). \(step.title)")
                        .font(.caption).foregroundStyle(Color.bgTextPrimary).lineLimit(1)
                    Spacer()
                    Text(label(step.status)).font(.caption2).foregroundStyle(Color.bgTextSecondary)
                }
            }
        }
        .padding(12).background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.bgJade.opacity(0.28), lineWidth: 0.5))
        .accessibilityIdentifier("chat.plan")
    }
    private func color(_ status: NexusStepStatus) -> Color {
        switch status {
        case .running: return Color.bgJadeHi
        case .passed: return Color.bgJade
        case .failed: return Color.orange
        case .skipped: return Color.bgTextSecondary
        case .pending: return Color.bgTextSecondary.opacity(0.6)
        }
    }
    private func label(_ status: NexusStepStatus) -> String {
        switch status {
        case .pending: return "待做"
        case .running: return "进行中"
        case .passed: return "完成"
        case .failed: return "失败"
        case .skipped: return "跳过"
        }
    }
}
