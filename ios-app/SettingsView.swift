//
//  SettingsView.swift
//  Black-God AI
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showResetAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // 背景
                LinearGradient(
                    colors: [Color(hex: "0f0c29"), Color(hex: "302b63"), Color(hex: "24243e")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // API 设置
                        SettingsSection(title: "🔧 API 设置") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("API 地址")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                TextField("http://8.222.169.202/v1/messages", text: $viewModel.apiURL)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .autocapitalization(.none)
                                    .keyboardType(.URL)
                                
                                Button(action: {
                                    viewModel.saveSettings()
                                    showSuccessToast()
                                }) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("保存设置")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                            }
                        }
                        
                        // 数据管理
                        SettingsSection(title: "💾 数据管理") {
                            VStack(spacing: 12) {
                                SettingsButton(
                                    icon: "trash.fill",
                                    title: "清空聊天记录",
                                    color: .red
                                ) {
                                    showResetAlert = true
                                }
                                
                                SettingsButton(
                                    icon: "square.and.arrow.up.fill",
                                    title: "导出对话",
                                    color: .blue
                                ) {
                                    viewModel.exportChat()
                                }
                            }
                        }
                        
                        // 关于
                        SettingsSection(title: "ℹ️ 关于") {
                            VStack(alignment: .leading, spacing: 16) {
                                InfoRow(label: "版本", value: "1.0.0")
                                InfoRow(label: "服务器", value: "8.222.169.202")
                                InfoRow(label: "工具数量", value: "14 个")
                                
                                Divider()
                                    .background(Color.white.opacity(0.2))
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("✨ 功能特性")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    ForEach(features, id: \.self) { feature in
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text(feature)
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 版权
                        Text("© 2026 Black-God Team\n完全原创 · 完全免费 · 完全无限制")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.top)
                    }
                    .padding()
                }
            }
            .navigationTitle("⚙️ 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("确认清空", isPresented: $showResetAlert) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    viewModel.clearHistory()
                    dismiss()
                }
            } message: {
                Text("所有聊天记录将被清空，此操作不可撤销")
            }
        }
    }
    
    let features = [
        "🔍 网页搜索",
        "🎨 AI 图片生成",
        "📱 APK 下载",
        "🌐 浏览器操作",
        "💾 数据库查询",
        "📝 记忆系统",
        "💻 代码执行",
        "🐳 Docker 操作"
    ]
    
    func showSuccessToast() {
        // 简单的成功提示
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            
            content
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
        }
    }
}

// MARK: - Settings Button
struct SettingsButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    SettingsView(viewModel: ChatViewModel())
}
