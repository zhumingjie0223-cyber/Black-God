//
//  APIConfigView.swift — API 配置页（按权哥要求：填一个 key 自动识别）
//  私人版专属：显示 11 公开 + 8 隐藏平台
//

import SwiftUI

struct APIConfigView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("api_base") var apiBase = ""
    @AppStorage("api_key") var apiKey = ""
    @AppStorage("api_model") var apiModel = "auto"
    @Environment(\.dismiss) var dismiss
    
    @State private var detectedProvider: String = ""

    // 11 公开平台预设（无推荐，用户自选）
    let publicPresets: [(String, String, String, String)] = [
        ("Anthropic 官方", "https://api.anthropic.com/v1", "sk-ant-...", "auto"),
        ("OpenAI 官方", "https://api.openai.com/v1", "sk-...", "auto"),
        ("Google Gemini", "https://generativelanguage.googleapis.com/v1beta", "AIza...", "auto"),
        ("xAI (Grok)", "https://api.x.ai/v1", "xai-...", "auto"),
        ("POE", "https://api.poe.com/v1", "sk-poe-...", "auto"),
        ("OpenRouter", "https://openrouter.ai/api/v1", "sk-or-...", "auto"),
        ("apiclaude", "https://apiclaude.cc/v1", "...", "auto"),
    ]
    
    // 8 隐藏平台（💎 私人版彩蛋）
    let hiddenPresets: [(String, String, String)] = [
        ("Cursor IDE", "https://api.cursor.sh/v1", "F12 → Local Storage → token"),
        ("Windsurf", "https://api.codeium.com/v1", "F12 → Network → Authorization"),
        ("Bolt.new", "https://api.bolt.new/v1", "F12 → Network → x-api-key"),
        ("v0.dev", "https://api.v0.dev/v1", "F12 → Network → authorization"),
        ("Replit", "https://api.replit.com/v1", "F12 → Cookies → connect.sid"),
        ("Lovable", "https://api.lovable.dev/v1", "F12 → Network → authorization"),
        ("Claude.ai Web", "https://claude.ai/api", "F12 → Cookies → sessionKey"),
        ("ChatGPT Web", "https://chatgpt.com/backend-api", "F12 → Network → Bearer token"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // ===== 智能识别区（按权哥要求：填一个 key 自动识别）=====
                    VStack(alignment: .leading, spacing: 12) {
                        Text("🔑 智能识别")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.bgGold)
                        
                        Text("填一个 API Key，自动识别网关")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.bgTextSecondary)
                        
                        // API Key 输入
                        SecureField("粘贴 API Key（sk-... / AIza... / xai-...）", text: $apiKey)
                            .font(.bgBody())
                            .foregroundStyle(Color.bgTextPrimary)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgCardLight))
                            .onChange(of: apiKey) { _, newValue in
                                detectProvider(newValue)
                            }
                        
                        // 识别结果
                        if !detectedProvider.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.bgGold)
                                Text("已识别: \(detectedProvider)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.bgTextPrimary)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgGold.opacity(0.1)))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.bgCardLight.opacity(0.5)))
                    
                    Divider().background(Color.bgGold.opacity(0.3))
                    
                    // ===== 11 公开平台 =====
                    VStack(alignment: .leading, spacing: 10) {
                        Text("公开平台").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.bgTextSecondary)
                        ForEach(publicPresets, id: \.0) { preset in
                            Button {
                                appState.haptic(.light)
                                apiBase = preset.1
                                apiKey = preset.2
                                apiModel = preset.3
                                detectProvider(preset.2)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.0)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Color.bgTextPrimary)
                                        Text(preset.1)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.bgTextSecondary)
                                    }
                                    Spacer()
                                    if apiBase == preset.1 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.bgGold)
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgCardLight))
                            }
                        }
                    }
                    
                    // ===== 8 隐藏平台（私人版直接显示）=====
                    VStack(alignment: .leading, spacing: 10) {
                        Text("隐藏平台")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.bgGold)
                        
                        Text("网页 App API 抓取（客户自行发掘 F12）")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bgTextSecondary)
                        
                        ForEach(hiddenPresets, id: \.0) { preset in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(preset.0)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Color.bgTextPrimary)
                                        Spacer()
                                        Button {
                                            appState.haptic(.light)
                                            apiBase = preset.1
                                        } label: {
                                            Text("使用")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color.bgGold)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.bgGold.opacity(0.2)))
                                        }
                                    }
                                    Text("抓取方法: \(preset.2)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.bgTextSecondary.opacity(0.8))
                                        .padding(.leading, 4)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgGold.opacity(0.05)))
                            }
                        }
                    }
                    
                    Divider().background(Color.bgGold.opacity(0.3))
                    
                    // ===== 手动覆盖（高级）=====
                    VStack(alignment: .leading, spacing: 12) {
                        Text("手动覆盖（高级）")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.bgTextSecondary)
                        
                        fieldGroup("API 地址", text: $apiBase, placeholder: "https://...")
                        fieldGroup("模型名", text: $apiModel, placeholder: "auto")
                    }
                    
                    // 保存
                    Button {
                        appState.haptic(.medium)
                        dismiss()
                    } label: {
                        Text("保存").font(.bgHeadline())
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(LinearGradient.goldGradient).foregroundStyle(Color.bgDark)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.top, 8)

                    Text("私人版专属：自动识别 11 公开 + 8 隐藏平台。配置只存本机，不上传。")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.bgTextSecondary.opacity(0.7))
                }
                .padding(20)
            }
            .background(LinearGradient.darkGradient.ignoresSafeArea())
            .navigationTitle("API 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }.foregroundStyle(Color.bgGold)
                }
            }
        }
        .onAppear {
            detectProvider(apiKey)
        }
    }
    
    // 按权哥要求：智能识别网关
    func detectProvider(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty {
            detectedProvider = ""
            return
        }
        
        // Anthropic
        else if t.hasPrefix("sk-ant-") || t.hasPrefix("ant-") {
            detectedProvider = "Anthropic 官方"
            apiBase = "https://api.anthropic.com/v1"
            apiModel = "auto"
        }
        // xAI (Grok)
        else if t.hasPrefix("xai-") || t.hasPrefix("grok-") || t.contains("x.ai") {
            detectedProvider = "xAI (Grok)"
            apiBase = "https://api.x.ai/v1"
            apiModel = "auto"
        }
        // Google Gemini
        else if t.hasPrefix("aiza") || t.hasPrefix("ya29") {
            detectedProvider = "Google Gemini"
            apiBase = "https://generativelanguage.googleapis.com/v1beta"
            apiModel = "auto"
        }
        // POE
        else if t.hasPrefix("sk-poe-") || t.hasPrefix("sk-pk-") {
            detectedProvider = "POE"
            apiBase = "https://api.poe.com/v1"
            apiModel = "auto"
        }
        // OpenRouter
        else if t.hasPrefix("sk-or-") {
            detectedProvider = "OpenRouter"
            apiBase = "https://openrouter.ai/api/v1"
            apiModel = "auto"
        }
        // 隐藏平台识别
        else if t.contains("cursor") || t.hasPrefix("cur_") {
            detectedProvider = "Cursor IDE (隐藏)"
            apiBase = "https://api.cursor.sh/v1"
            apiModel = "auto"
        }
        else if t.contains("windsurf") || t.contains("codeium") {
            detectedProvider = "Windsurf/Codeium (隐藏)"
            apiBase = "https://api.codeium.com/v1"
            apiModel = "auto"
        }
        else if t.contains("bolt") || t.contains("stackblitz") {
            detectedProvider = "Bolt.new (隐藏)"
            apiBase = "https://api.bolt.new/v1"
            apiModel = "auto"
        }
        else if t.contains("v0") || t.contains("vercel") {
            detectedProvider = "v0.dev (隐藏)"
            apiBase = "https://api.v0.dev/v1"
            apiModel = "auto"
        }
        else if t.contains("replit") || t.contains("repl") {
            detectedProvider = "Replit (隐藏)"
            apiBase = "https://api.replit.com/v1"
            apiModel = "auto"
        }
        else if t.contains("lovable") || t.contains("gpt-engineer") {
            detectedProvider = "Lovable (隐藏)"
            apiBase = "https://api.lovable.dev/v1"
            apiModel = "auto"
        }
        else if t.contains("claude.ai") || t.hasPrefix("sk-ant-sid") {
            detectedProvider = "Claude.ai Web (隐藏)"
            apiBase = "https://claude.ai/api"
            apiModel = "auto"
        }
        else if t.contains("chatgpt.com") || t.hasPrefix("eyjalgi") {
            detectedProvider = "ChatGPT Web (隐藏)"
            apiBase = "https://chatgpt.com/backend-api"
            apiModel = "auto"
        }
        // 默认：OpenAI 兼容
        else {
            detectedProvider = "OpenAI 兼容"
            apiBase = "https://api.openai.com/v1"
            apiModel = "auto"
        }
    }

    func fieldGroup(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.bgTextSecondary)
            TextField(placeholder, text: text)
                .font(.system(size: 13))
                .foregroundStyle(Color.bgTextPrimary)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgCardLight))
        }
    }
}
