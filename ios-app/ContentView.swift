//
//  ContentView.swift
//  Black-God AI - 优化版
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showSettings = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [Color(hex: "0f0c29"), Color(hex: "302b63"), Color(hex: "24243e")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 消息列表
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(viewModel.messages) { message in
                                    MessageBubbleView(message: message)
                                        .id(message.id)
                                        .transition(.asymmetric(
                                            insertion: .scale.combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }
                                
                                if viewModel.isLoading {
                                    LoadingIndicatorView()
                                }
                            }
                            .padding()
                        }
                        .onChange(of: viewModel.messages.count) { _ in
                            if let lastMessage = viewModel.messages.last {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // 输入区域
                    InputBarView(
                        text: $viewModel.inputText,
                        isLoading: viewModel.isLoading,
                        onSend: { viewModel.sendMessage() }
                    )
                }
            }
            .navigationTitle("🤖 Black-God AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { viewModel.clearHistory() }) {
                            Label("清空历史", systemImage: "trash")
                        }
                        Button(action: { viewModel.exportChat() }) {
                            Label("导出对话", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
        .onAppear {
            viewModel.addWelcomeMessage()
        }
    }
}

// MARK: - 消息气泡
struct MessageBubbleView: View {
    let message: Message
    @State private var showCopyAlert = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser { Spacer(minLength: 60) }
            
            if !message.isUser {
                // AI 头像
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("🤖")
                            .font(.system(size: 16))
                    )
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // 消息内容
                Group {
                    if message.type == .image {
                        AsyncImage(url: URL(string: message.imageURL ?? "")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(12)
                        } placeholder: {
                            ProgressView()
                                .frame(width: 200, height: 200)
                        }
                        .frame(maxWidth: 250)
                    } else {
                        Text(message.text)
                            .font(.system(size: 16))
                            .padding(14)
                            .background(
                                message.isUser ?
                                LinearGradient(
                                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color(hex: "1e1e1e").opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(18)
                            .shadow(color: message.isUser ? Color.purple.opacity(0.3) : Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                }
                .contextMenu {
                    Button(action: { copyToClipboard(message.text) }) {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    Button(action: { shareMessage(message.text) }) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
                
                // 时间戳
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            if message.isUser {
                // 用户头像
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "f093fb"), Color(hex: "f5576c")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("👤")
                            .font(.system(size: 16))
                    )
            }
            
            if !message.isUser { Spacer(minLength: 60) }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.id)
    }
    
    func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        showCopyAlert = true
    }
    
    func shareMessage(_ text: String) {
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - 加载指示器
struct LoadingIndicatorView: View {
    @State private var animationAmount = 0.0
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 10, height: 10)
                    .scaleEffect(animationAmount == Double(index) ? 1.2 : 0.8)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animationAmount
                    )
            }
            Text("正在思考...")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(20)
        .onAppear {
            animationAmount = 1.0
        }
    }
}

// MARK: - 输入栏
struct InputBarView: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void
    
    @State private var showVoiceInput = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 语音输入按钮
            Button(action: { showVoiceInput = true }) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(22)
            }
            
            // 文本输入
            HStack {
                TextField("输入消息...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .disabled(isLoading)
                    .lineLimit(1...5)
                    .onSubmit(onSend)
                
                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.1))
            .cornerRadius(22)
            
            // 发送按钮
            Button(action: onSend) {
                Image(systemName: isLoading ? "stop.circle.fill" : "paperplane.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading ?
                            [Color.gray.opacity(0.3)] :
                            [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(22)
                    .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.3)
                .blur(radius: 10)
        )
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
}
