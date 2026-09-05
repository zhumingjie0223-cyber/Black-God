//
//  MonitorView.swift — 神枢本地运行监测
//
//  纯客户端：展示本地 AI 助手的能力指标（任务成功率、验证率、恢复率、延迟），
//  数据来自本地任务评测存储，不连任何远端服务。

import SwiftUI

struct MonitorView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var model = NexusMonitorModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("神枢监测").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                        Text("本地 AI 助手能力指标").font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    }
                    Spacer()
                    Button { model.refresh() } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 24)).foregroundStyle(Color.bgGold)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    MetricCard(title: "任务成功率", value: model.successRate, symbol: "checkmark.circle")
                    MetricCard(title: "验证率", value: model.verificationRate, symbol: "checkmark.shield")
                    MetricCard(title: "恢复率", value: model.recoveryRate, symbol: "arrow.triangle.2.circlepath")
                    MetricCard(title: "平均延迟", value: model.latencyText, symbol: "clock")
                    MetricCard(title: "任务记录", value: "\(model.recordCount)", symbol: "list.bullet.rectangle")
                }
                .padding(.horizontal, 16)

                if model.recordCount == 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("暂无任务记录", systemImage: "info.circle.fill").foregroundStyle(.orange)
                        Text("完成一次对话后，这里会展示 AI 助手的成功率、验证率等能力指标。")
                            .font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).bgCard().padding(.horizontal, 16)
                } else {
                    Text("指标基于本地 \(model.recordCount) 次任务记录，数据仅存于此设备。")
                        .font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16).bgCard().padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 50)
        .task { model.refresh() }
    }
}

@MainActor
final class NexusMonitorModel: ObservableObject {
    @Published private(set) var successRate = 0.0
    @Published private(set) var verificationRate = 0.0
    @Published private(set) var recoveryRate = 0.0
    @Published private(set) var latencyText = "—"
    @Published private(set) var recordCount = 0

    func refresh() {
        let store = NexusEvaluationStore()
        successRate = store.successRate
        verificationRate = store.verificationRate
        recoveryRate = store.recoveryRate
        recordCount = store.records.count
        let lat = store.averageLatency
        latencyText = lat == 0 ? "—" : String(format: "%.1fs", lat)
    }
}

private struct MetricCard: View {
    let title: String
    let value: Double
    let symbol: String
    var valueText: String { String(format: "%.0f%%", value * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(Color.bgCyan)
            Text(valueText).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.bgTextPrimary)
            Text(title).font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).bgCard()
    }
}
