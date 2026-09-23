//
//  MonitorView.swift — 神枢本地运行监测
//
//  本地运行统计不等于任务正确率；独立验收由用户在单独页面发起。

import SwiftUI

struct MonitorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showBenchmark = false
    @State private var showMetricNotes = false
    @StateObject private var model = NexusMonitorModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Text("神枢监测").font(.title2.weight(.semibold))
                        .foregroundStyle(Color.bgTextPrimary).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    refreshButton
                }
                recordSummary
                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                    MetricCard(title: "无警告答复率", valueText: model.successRateText, symbol: "text.bubble", sample: "\(model.recordCount) 次任务")
                    MetricCard(title: "模型自检通过率", valueText: model.verificationRateText, symbol: "checklist", sample: "\(model.recordCount) 次任务")
                    MetricCard(title: "重试答复率", valueText: model.recoveryRateText, symbol: "arrow.triangle.2.circlepath", sample: "\(model.recoveryAttemptCount) 次重试")
                    MetricCard(title: "平均耗时", valueText: model.latencyText, symbol: "clock", sample: "\(model.latencySampleCount) 条有效耗时")
                }
                benchmarkCard
                metricNotes
                recentTasks
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(Color.bgDark)
        .refreshable { model.refresh() }
        .task { model.refresh() }
        .sheet(isPresented: $showBenchmark) { NexusBenchmarkView() }
    }

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var recordSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            recordStatus
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.legacyCount > 0 {
                Text("\(model.legacyCount) 条旧记录未计入")
                    .font(.caption).foregroundStyle(Color.bgTextSecondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).bgFloating()
    }

    private var recordStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.lastError != nil ? "记录读取受阻" : model.recordCount == 0 ? "暂无可统计任务" : "本机任务记录", systemImage: "internaldrive")
                .font(.subheadline.weight(.medium)).foregroundStyle(Color.bgTextSecondary)
            Text("\(model.recordCount) 次任务")
                .font(.title2.weight(.medium)).monospacedDigit().foregroundStyle(Color.bgJadeHi)
                .accessibilityIdentifier("monitor.sample-count")
        }
    }

    private var refreshButton: some View {
        Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
            .buttonStyle(BGSecondaryButtonStyle())
            .accessibilityIdentifier("monitor.refresh")
    }

    private var benchmarkCard: some View {
        Button { showBenchmark = true } label: {
            Label("运行模型任务验收", systemImage: "play.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(BGPrimaryButtonStyle())
        .accessibilityIdentifier("benchmark.open")
    }

    private var metricNotes: some View {
        DisclosureGroup(isExpanded: $showMetricNotes) {
            VStack(alignment: .leading, spacing: 10) {
                Text("运行统计不代表任务正确率；模型自检由模型自身完成。")
                Text("每项指标下方列出样本数。重试仅计主动重试；耗时仅计有效记录。无样本显示 —。")
                Text("独立验收会另行运行任务，核对答案与工具证据。旧版记录仍保留。")
            }
            .font(.caption).foregroundStyle(Color.bgTextSecondary)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
        } label: {
            Label("指标说明", systemImage: "info.circle")
                .font(.subheadline).foregroundStyle(Color.bgTextSecondary).frame(minHeight: 44)
        }
        .tint(Color.bgJadeHi)
        .padding(.horizontal, 18).padding(.vertical, 4).bgFloating(cornerRadius: 20)
    }

    private var recentTasks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近任务").font(.headline).foregroundStyle(Color.bgTextPrimary)
                Spacer()
                Text("\(model.recentRecords.count) 条").font(.caption).foregroundStyle(Color.bgTextSecondary)
            }
            if model.recentRecords.isEmpty {
                Label("暂无任务", systemImage: "tray")
                    .font(.subheadline).foregroundStyle(Color.bgTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(model.recentRecords.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Divider().overlay(Color.bgJade.opacity(0.15)) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.task).font(.subheadline.weight(.medium)).foregroundStyle(Color.bgTextPrimary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            Text(record.success ? "已生成无警告答复" : "未完成或有警告")
                                .font(.caption).foregroundStyle(record.success ? Color.bgJadeHi : .orange)
                            Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(Color.bgTextSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.padding(18).bgFloating()
    }
}

@MainActor
final class NexusMonitorModel: ObservableObject {
    @Published private(set) var successRateText = "—"
    @Published private(set) var verificationRateText = "—"
    @Published private(set) var recoveryRateText = "—"
    @Published private(set) var latencyText = "—"
    @Published private(set) var recordCount = 0
    @Published private(set) var recoveryAttemptCount = 0
    @Published private(set) var latencySampleCount = 0
    @Published private(set) var recentRecords: [NexusEvaluationRecord] = []
    @Published private(set) var legacyCount = 0
    @Published private(set) var lastError: String?

    func refresh() {
        let store = NexusEvaluationStore()
        successRateText = percent(store.responseRate)
        verificationRateText = percent(store.reviewRate)
        recoveryRateText = percent(store.recoveryRate)
        recordCount = store.current.count
        recoveryAttemptCount = store.recoveryAttempts
        latencySampleCount = store.current.filter { $0.latency.isFinite && $0.latency >= 0 }.count
        recentRecords = Array(store.current.suffix(5).reversed())
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
    let sample: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(Color.bgJadeHi)
            Text(valueText).font(.title.weight(.medium)).monospacedDigit()
                .foregroundStyle(valueText == "—" ? Color.bgTextSecondary : Color.bgJadeHi)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline).foregroundStyle(Color.bgTextPrimary)
                Text(sample).font(.caption).foregroundStyle(Color.bgTextSecondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18).bgFloating(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}
