//
//  ToolsView.swift — 工具页（红队工具集）
//

import SwiftUI

struct ToolItem: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    let desc: String
    let color: Color
}

struct ToolsView: View {
    @EnvironmentObject var appState: AppState
    let tools = [
        ToolItem(icon: "chevron.left.forwardslash.chevron.right", name: "黑神编码", desc: "理解→生成→调试→重构", color: .bgCyan),
        ToolItem(icon: "shield.lefthalf.filled", name: "安全沙箱", desc: "隔离执行·红队强化", color: .bgPurple),
        ToolItem(icon: "network", name: "渗透测试", desc: "扫描·爆破·注入", color: .red),
        ToolItem(icon: "antenna.radiowaves.left.and.right", name: "C2远控", desc: "后门·持久化·提权", color: .orange),
        ToolItem(icon: "lock.shield", name: "免杀过盾", desc: "Payload·混淆·绕过", color: .green),
        ToolItem(icon: "doc.text.magnifyingglass", name: "逆向分析", desc: "APK·IPA·脱壳", color: .bgGold),
        ToolItem(icon: "terminal", name: "Shell终端", desc: "完整Linux环境", color: .bgCyan),
        ToolItem(icon: "key.horizontal", name: "密码破解", desc: "Hash·字典·爆破", color: .pink)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("工具箱").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                    .padding(.horizontal, 16).padding(.top, 8)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(tools) { tool in
                        Button { appState.haptic() } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: tool.icon).font(.system(size: 26)).foregroundStyle(tool.color)
                                Text(tool.name).font(.bgHeadline()).foregroundStyle(Color.bgTextPrimary)
                                Text(tool.desc).font(.system(size: 12)).foregroundStyle(Color.bgTextSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 120).bgCard()
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 50)
    }
}
