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
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            PresenceStrip(snapshot: vm.presence) { vm.actOnPresence() }
                .padding(.horizontal, 16).padding(.bottom, 8)
            NexusActivityPanel(chat: vm, practice: vm.practice).padding(.horizontal, 16).padding(.bottom, 8)
            if let plan = vm.currentPlan, !plan.steps.isEmpty, vm.isTyping || vm.canResume {
                NexusPlanStrip(plan: plan).padding(.horizontal, 16).padding(.bottom, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if vm.messages.isEmpty {
                            ChatEmptyState(pulseNote: vm.pulseNote) { input = $0; inputFocused = true }
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
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(vm.messages.last?.id, anchor: .bottom) }
                }
            }
            if !vm.isTyping, let task = vm.taskCheckpoint, NexusSkillContent.candidate(from: task) != nil {
                Button("把本次流程整理为技能") { skillDraft = NexusSkillDraft(source: task) }
                    .font(.caption).padding(8).accessibilityIdentifier("skills.fromTask")
            }
            if vm.canResume, let task = vm.taskCheckpoint {
                VStack(alignment: .leading, spacing: 6) {
                    Text("有未完成任务").font(.caption.bold())
                    Text(task.goal).font(.caption).lineLimit(2)
                    Text("继续时会先检查已有进度；发送新问题会替换这份恢复记录。")
                        .font(.caption2).foregroundStyle(Color.bgTextSecondary)
                    HStack {
                        Button("继续任务") { vm.resume() }.accessibilityIdentifier("chat.resume")
                        Spacer()
                        Button("结束此任务") { vm.discardRecovery() }.accessibilityIdentifier("chat.discard")
                    }
                }.padding(12).background(Color.bgCard).padding(.horizontal, 16)
            }
            if let status = vm.statusHint {
                Text(status).font(.caption).foregroundStyle(Color.bgTextSecondary).padding(8)
            }
            if let error = vm.lastError {
                HStack {
                    Text(error).font(.caption).foregroundStyle(Color.bgTextSecondary)
                    Spacer()
                    if vm.canRetry { Button("重试") { vm.retry() } }
                    if !vm.apiKeyConfigured { Button("配置连接") { showConnection = true }.accessibilityIdentifier("api.open") }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            if vm.canRegenerate {
                HStack {
                    Spacer()
                    Button("重新生成上一则") { vm.regenerate() }
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.bgJadeHi)
                        .accessibilityIdentifier("chat.regenerate")
                }.padding(.horizontal, 16).padding(.bottom, 4)
            }
            inputBar
        }
        .padding(.top, 50)
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
    }

    var chatHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.bgGoldLight)
                .frame(width: 44, height: 44).background(Color.bgCard).clipShape(Circle())
                .overlay(Circle().stroke(LinearGradient.goldGradient, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text("Black God AI").font(.bgHeadline()).foregroundStyle(Color.bgTextPrimary)
                    .accessibilityIdentifier("chat.title")
                HStack(spacing: 4) {
                    PresenceDot(duration: vm.presence.breath)
                    Text(vm.currentMood).font(.system(size: 11)).foregroundStyle(Color.bgTextSecondary)
                        .accessibilityIdentifier("chat.mood")
                }
            }
            Spacer()
            Button { showConnection = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18)).foregroundStyle(Color.bgGold)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12).background(Color.bgDark.opacity(0.95))
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = false }
    }

    var inputBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChatComposerChip.all, id: \.title) { chip in
                        Button(chip.title) { input = chip.prompt; inputFocused = true }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.bgJadeHi)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.bgCardLight))
                            .overlay(Capsule().stroke(Color.bgJade.opacity(0.35), lineWidth: 0.5))
                            .accessibilityIdentifier(chip.accessibilityID)
                    }
                }
            }
            HStack(spacing: 10) {
                TextField("跟Black God AI说点什么…", text: $input, axis: .vertical)
                    .focused($inputFocused).font(.bgBody()).foregroundStyle(Color.bgTextPrimary).lineLimit(1...4)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Color.bgCardLight))
                    .submitLabel(.send)
                    .accessibilityIdentifier("chat.input")
                    .onSubmit { sendCurrent() }
                Button {
                    sendCurrent()
                } label: {
                    Image(systemName: vm.isTyping ? "stop.circle.fill" : "arrow.up.circle.fill").font(.system(size: 34))
                        .foregroundStyle(input.isEmpty ? AnyShapeStyle(Color.bgTextSecondary) : AnyShapeStyle(LinearGradient.goldGradient))
                }.disabled(!vm.isTyping && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(vm.isTyping ? "停止回答" : "发送消息")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).background(Color.bgDark.opacity(0.98))
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
    var isUser: Bool { message.role == "user" }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 50) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(message.content).font(.bgBody()).textSelection(.enabled)
                    .foregroundStyle(isUser ? Color.bgDark : Color.bgTextPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(isUser ? AnyShapeStyle(LinearGradient.goldGradient) : AnyShapeStyle(Color.bgCard))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if !isUser, let evidence = message.evidence, !evidence.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(evidence.enumerated()), id: \.offset) { _, chip in
                                Text(chip)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.bgJadeHi)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.bgCardLight))
                                    .overlay(Capsule().stroke(Color.bgJade.opacity(0.35), lineWidth: 0.5))
                            }
                        }
                    }
                    .accessibilityIdentifier("chat.evidence")
                }
            }
            if !isUser { Spacer(minLength: 50) }
        }
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
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(Double(i) * 0.12), value: on)
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
    static let all = [
        ChatComposerChip(title: "计算", prompt: "帮我计算并核对结果：", accessibilityID: "chat.chip.calc"),
        ChatComposerChip(title: "规划", prompt: "把这件事拆成可检查的步骤：", accessibilityID: "chat.chip.plan"),
        ChatComposerChip(title: "枢语", prompt: "用枢语检索并造一个词：", accessibilityID: "chat.chip.shuyu"),
        ChatComposerChip(title: "一息", prompt: "用枢语一息看现在：", accessibilityID: "chat.chip.pulse")
    ]
}

struct PresenceDot: View {
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
        on = false
        withAnimation(.easeInOut(duration: max(0.6, value)).repeatForever(autoreverses: true)) { on = true }
    }
}

struct PresenceStrip: View {
    let snapshot: NexusPresenceSnapshot
    let act: () -> Void
    @State private var on = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.nextWork).font(.caption.bold()).foregroundStyle(Color.bgJadeHi)
            if !snapshot.thread.isEmpty {
                Text(snapshot.thread).font(.caption).foregroundStyle(Color.bgTextPrimary).lineLimit(2)
            }
            if snapshot.action != .none {
                Button(snapshot.actionTitle, action: act)
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.bgJadeHi)
                    .accessibilityIdentifier("chat.act")
            }
        }
        .padding(12).background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.bgJade.opacity(0.28), lineWidth: 0.5))
        .scaleEffect(leaning(snapshot.stance) ? (on ? 1.0 : 0.98) : 1)
        .opacity(breathing(snapshot.stance) ? (on ? 1 : 0.72) : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.presence")
        .onAppear { breathe(snapshot.stance) }
        .onChange(of: snapshot.stance) { _, value in breathe(value) }
    }
    private func breathing(_ stance: String) -> Bool {
        ["working", "speaking", "listening", "hitching", "holding", "retracting", "watching", "noticing", "settled", "echoing", "exhaling"].contains(stance)
    }
    private func leaning(_ stance: String) -> Bool {
        ["speaking", "hitching", "retracting", "watching", "noticing", "exhaling"].contains(stance)
    }
    private func breathe(_ stance: String) {
        guard breathing(stance) else { on = false; return }
        on = false
        let duration: Double
        switch stance {
        case "speaking": duration = 0.7
        case "working": duration = 0.9
        case "exhaling": duration = 1.0
        case "listening": duration = 1.1
        case "retracting": duration = 1.3
        case "hitching": duration = 1.5
        case "watching": duration = 1.4
        case "noticing": duration = 1.8
        case "holding": duration = 2.0
        case "echoing": duration = 2.2
        default: duration = 3.2
        }
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) { on = true }
    }
}

struct ChatEmptyState: View {
    var pulseNote: String? = nil
    let use: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pulseNote.map { "Black God AI 在场 · \($0)" } ?? "Black God AI 在场。直接说出你要完成的事，它会按需使用内置工具执行并核对结果。")
                .foregroundStyle(Color.bgTextSecondary)
            ForEach(["计算 12 个月每月存 500 元的累计金额，并核对结果。", "用枢语造一个关于「锚点」的词，并核对编号。", "把整理账单拆成可检查的三步计划。"], id: \.self) { sample in
                Button(sample) { use(sample) }
                    .font(.subheadline).foregroundStyle(Color.bgTextPrimary).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.bgJade.opacity(0.2), lineWidth: 0.5))
            }
        }.padding(.vertical, 12).accessibilityIdentifier("chat.empty")
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
