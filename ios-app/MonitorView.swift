//
//  MonitorView.swift — 神枢本地运行监测
//
//  本地运行统计不等于任务正确率；独立验收由用户在单独页面发起。

import SwiftUI

struct MonitorView: View {
    @EnvironmentObject var appState: AppState
    @State private var showBenchmark = false
    @StateObject private var model = NexusMonitorModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("神枢监测").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                        Text("运行记录与独立验收").font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    }
                    Spacer()
                    Button { model.refresh() } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 24)).foregroundStyle(Color.bgGold)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    MetricCard(title: "无警告答复率", valueText: model.successRateText, symbol: "checkmark.circle")
                    MetricCard(title: "模型复核通过率", valueText: model.verificationRateText, symbol: "checkmark.shield")
                    MetricCard(title: "重试答复率", valueText: model.recoveryRateText, symbol: "arrow.triangle.2.circlepath")
                    MetricCard(title: "平均延迟", valueText: model.latencyText, symbol: "clock")
                    MetricCard(title: "任务记录", valueText: "\(model.recordCount)", symbol: "list.bullet.rectangle")
                }
                .padding(.horizontal, 16)

                Button("运行模型任务验收") { showBenchmark = true }
                    .accessibilityIdentifier("benchmark.open").padding(.horizontal, 16)
                Text("上方是运行统计，不代表任务正确率。模型复核是自我检查；重试答复率只统计明确发起过重试的任务。")
                    .font(.caption).foregroundStyle(Color.bgTextSecondary).padding(.horizontal, 16)
                if let error = model.lastError { Text(error).foregroundStyle(.red).padding(.horizontal, 16) }
                if model.legacyCount > 0 {
                    Text("旧版记录\(model.legacyCount)条未纳入新指标，原记录仍保留。")
                        .font(.caption).foregroundStyle(Color.bgTextSecondary).padding(.horizontal, 16)
                }
                if model.recordCount == 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("暂无任务记录", systemImage: "info.circle.fill").foregroundStyle(.orange)
                        Text("完成一次对话后，这里会展示答复状态、模型自我复核和耗时；任务正确性需要另行验收。")
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
        .sheet(isPresented: $showBenchmark) { NexusBenchmarkView() }
    }
}

@MainActor
final class NexusMonitorModel: ObservableObject {
    @Published private(set) var successRateText = "—"
    @Published private(set) var verificationRateText = "—"
    @Published private(set) var recoveryRateText = "—"
    @Published private(set) var latencyText = "—"
    @Published private(set) var recordCount = 0
    @Published private(set) var legacyCount = 0
    @Published private(set) var lastError: String?

    func refresh() {
        let store = NexusEvaluationStore()
        successRateText = percent(store.responseRate)
        verificationRateText = percent(store.reviewRate)
        recoveryRateText = percent(store.recoveryRate)
        recordCount = store.current.count
        legacyCount = store.legacyCount
        lastError = store.lastError
        let lat = store.averageLatency
        latencyText = lat.map { String(format: "%.1fs", $0) } ?? "—"
    }

    private func percent(_ v: Double?) -> String { v.map { String(format: "%.0f%%", $0 * 100) } ?? "—" }
}

private struct MetricCard: View {
    let title: String
    let valueText: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(Color.bgCyan)
            Text(valueText).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.bgTextPrimary)
            Text(title).font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).bgCard()
    }
}
