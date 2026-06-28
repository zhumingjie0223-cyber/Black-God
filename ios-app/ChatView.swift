//
//  ChatView.swift — 赵思涵对话界面
//

import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    var content: String
    var mood: String = "normal"
}

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = ChatViewModel()
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(vm.messages) { msg in MessageBubble(message: msg).id(msg.id) }
                        if vm.isTyping { TypingIndicator().id("typing") }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 100)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(vm.messages.last?.id, anchor: .bottom) }
                }
            }
            inputBar
        }
        .padding(.top, 50)
    }

    var chatHeader: some View {
        HStack(spacing: 12) {
            Image("sihan-avatar").resizable().scaledToFill()
                .frame(width: 44, height: 44).clipShape(Circle())
                .overlay(Circle().stroke(LinearGradient.goldGradient, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text("赵思涵").font(.bgHeadline()).foregroundStyle(Color.bgTextPrimary)
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(vm.currentMood).font(.system(size: 11)).foregroundStyle(Color.bgTextSecondary)
                }
            }
            Spacer()
            Button { appState.haptic() } label: {
                Image(systemName: "phone.fill").font(.system(size: 18)).foregroundStyle(Color.bgGold)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12).background(Color.bgDark.opacity(0.95))
    }

    var inputBar: some View {
        HStack(spacing: 10) {
            Button { appState.haptic() } label: {
                Image(systemName: "mic.fill").font(.system(size: 20)).foregroundStyle(Color.bgGold)
            }
            TextField("跟思涵说点什么…", text: $input, axis: .vertical)
                .focused($inputFocused).font(.bgBody()).foregroundStyle(Color.bgTextPrimary).lineLimit(1...4)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.bgCardLight))
            Button {
                guard !input.isEmpty else { return }
                appState.haptic(.medium); vm.send(input); input = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                    .foregroundStyle(input.isEmpty ? AnyShapeStyle(Color.bgTextSecondary) : AnyShapeStyle(LinearGradient.goldGradient))
            }.disabled(input.isEmpty)
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
            Text(message.content).font(.bgBody())
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
