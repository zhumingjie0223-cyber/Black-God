//
//  ChatView.swift — Black God AI对话界面
//

import SwiftUI

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
            NexusActivityPanel(chat: vm, practice: vm.practice).padding(.horizontal, 16).padding(.bottom, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if vm.messages.isEmpty {
                            Text("直接说出你要完成的事。Black God 会按需使用内置工具执行并核对结果，无需你输入代码。")
                                .foregroundStyle(Color.bgTextSecondary).padding(.vertical, 32)
                        }
                        ForEach(vm.messages) { msg in
                            MessageBubble(message: msg).id(msg.id).contextMenu {
                                if msg.role == "user" {
                                    Button("保存为长期记忆") { memoryMessage = msg }
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
            inputBar
        }
        .padding(.top, 50)
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
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(vm.currentMood).font(.system(size: 11)).foregroundStyle(Color.bgTextSecondary)
                }
            }
            Spacer()
            Button { showConnection = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18)).foregroundStyle(Color.bgGold)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12).background(Color.bgDark.opacity(0.95))
    }

    var inputBar: some View {
        HStack(spacing: 10) {
            TextField("跟Black God AI说点什么…", text: $input, axis: .vertical)
                .focused($inputFocused).font(.bgBody()).foregroundStyle(Color.bgTextPrimary).lineLimit(1...4)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.bgCardLight))
            Button {
                if vm.isTyping { vm.cancel(); return }
                guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                appState.haptic(.medium)
                vm.send(input)
                if vm.isTyping { input = "" }
            } label: {
                Image(systemName: vm.isTyping ? "stop.circle.fill" : "arrow.up.circle.fill").font(.system(size: 34))
                    .foregroundStyle(input.isEmpty ? AnyShapeStyle(Color.bgTextSecondary) : AnyShapeStyle(LinearGradient.goldGradient))
            }.disabled(!vm.isTyping && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(vm.isTyping ? "停止回答" : "发送消息")
        }
        .padding(.horizontal, 16).padding(.vertical, 12).background(Color.bgDark.opacity(0.98))
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == "user" }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 50) }
            Text(message.content).font(.bgBody()).textSelection(.enabled)
                .foregroundStyle(isUser ? Color.bgDark : Color.bgTextPrimary)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(isUser ? AnyShapeStyle(LinearGradient.goldGradient) : AnyShapeStyle(Color.bgCard))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !isUser { Spacer(minLength: 50) }
        }
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(Color.bgGold).frame(width: 7, height: 7)
                        .opacity(phase == Double(i) ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            Spacer()
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { phase = 2 } }
    }
}
