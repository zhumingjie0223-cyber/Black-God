//
//  ToolsView.swift — 能力页：展示神枢真实的 Agent 执行闭环与工具总线
//

import SwiftUI

struct CapabilityItem: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    let desc: String
}

struct ToolsView: View {
    @EnvironmentObject var appState: AppState

    private let loop: [CapabilityItem] = [
        CapabilityItem(icon: "list.bullet.rectangle", name: "规划", desc: "把目标拆成可执行、可验证的步骤"),
        CapabilityItem(icon: "gearshape.2", name: "执行", desc: "按步调用工具，多轮闭环推进"),
        CapabilityItem(icon: "checkmark.shield", name: "验证", desc: "独立校验结果，覆盖目标关键词"),
        CapabilityItem(icon: "arrow.triangle.2.circlepath", name: "重规划", desc: "验证未过时在预算内自动重试"),
        CapabilityItem(icon: "shippingbox", name: "交付", desc: "汇总每步结果，产出最终答复")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("能力").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                    .padding(.horizontal, 16).padding(.top, 8)

                sectionTitle("执行闭环")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(loop) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: item.icon).font(.system(size: 24)).foregroundStyle(Color.bgGoldLight)
                            Text(item.name).font(.bgHeadline()).foregroundStyle(Color.bgTextPrimary)
                            Text(item.desc).font(.system(size: 12)).foregroundStyle(Color.bgTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 116).bgCard()
                    }
                }
                .padding(.horizontal, 16)

                sectionTitle("工具总线")
                VStack(spacing: 0) {
                    ForEach(Array(NexusToolCatalog.definitions.enumerated()), id: \.offset) { index, def in
                        if index > 0 { Divider().background(Color.bgCardLight) }
                        ToolBusRow(definition: def, policy: NexusPermissionGate.standard.policies[def.name])
                    }
                }
                .bgCard().padding(.horizontal, 16)

                Text("工具在本机执行；涉及写入或系统操作的工具需经你确认后才会运行。")
                    .font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 50)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.bgHeadline()).foregroundStyle(Color.bgTextSecondary)
            .padding(.horizontal, 16)
    }
}

private struct ToolBusRow: View {
    let definition: NexusToolDefinition
    let policy: NexusToolPolicy?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.bgCyan).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name).font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
                Text(definition.description).font(.system(size: 12)).foregroundStyle(Color.bgTextSecondary)
            }
            Spacer()
            Text(badge).font(.system(size: 11, weight: .medium))
                .foregroundStyle(needsApproval ? Color.orange : Color.green)
        }
        .padding(.vertical, 12).padding(.horizontal, 4)
    }

    private var needsApproval: Bool { policy?.requiresApproval ?? false }
    private var badge: String { needsApproval ? "需确认" : "只读" }
    private var icon: String {
        switch definition.name {
        case "read_file": return "doc.text"
        case "write_file": return "square.and.pencil"
        case "shell": return "terminal"
        default: return "text.bubble"
        }
    }
}
