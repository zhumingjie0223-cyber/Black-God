//
// MonitorView.swift — 神枢真实可观测控制面
//
// 不生成随机 CPU/内存/服务状态。所有数值来自 Cloudflare Worker `/stats`，
// 未配置 Keychain owner token 或网络失败时明确展示不可用原因。

import SwiftUI

@MainActor
final class NexusMonitorModel: ObservableObject {
    @Published private(set) var stats: NexusStatsResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var refreshedAt: Date?

    func refresh(baseURL: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let client = try NexusClient(base: baseURL)
            stats = try await client.stats()
            errorText = nil
            refreshedAt = Date()
        } catch {
            stats = nil
            errorText = error.localizedDescription
        }
    }
}

struct MonitorView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("nexus_base") private var nexusBase = "https://nexus-do.jjiebbay.workers.dev"
    @StateObject private var model = NexusMonitorModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("神枢监测").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                        Text("Cloudflare Worker 真实状态").font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    }
                    Spacer()
                    Button { Task { await model.refresh(baseURL: nexusBase) } } label: {
                        Image(systemName: model.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise.circle")
                            .font(.system(size: 24)).foregroundStyle(Color.bgGold)
                    }
                    .disabled(model.isLoading)
                }
                .padding(.horizontal, 16).padding(.top, 8)

                if let stats = model.stats {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        MetricCard(title: "运行时间", value: formatUptime(stats.uptimeSeconds), symbol: "clock")
                        MetricCard(title: "存储估算", value: "\(stats.storageSizeKB ?? "—") KB", symbol: "externaldrive")
                        MetricCard(title: "经验记录", value: "\(stats.experienceCount ?? 0)", symbol: "brain")
                        MetricCard(title: "能力登记", value: "\(stats.capabilities ?? 0)", symbol: "square.grid.2x2")
                        MetricCard(title: "世界实体", value: "\(stats.worldEntities ?? 0)", symbol: "point.3.connected.trianglepath.dotted")
                        MetricCard(title: "内在记录", value: "\(stats.innerVoiceCount ?? 0)", symbol: "waveform.path.ecg")
                    }
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                            Text("已从神枢读取运行状态").font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
                        }
                        Text("引擎版本 \(stats.soulVersion ?? 0) · \(model.refreshedAt?.formatted(date: .omitted, time: .standard) ?? "刚刚") 更新")
                            .font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).bgCard().padding(.horizontal, 16)
                } else if let error = model.errorText {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("暂未获得神枢状态", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                        Text("请在「我的 → 神枢连接」保存有效 Worker 地址和主人令牌后重试。")
                            .font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).bgCard().padding(.horizontal, 16)
                } else {
                    ProgressView("正在读取神枢状态…")
                        .frame(maxWidth: .infinity).padding(28).bgCard().padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 50)
        .task { await model.refresh(baseURL: nexusBase) }
        .refreshable { await model.refresh(baseURL: nexusBase) }
    }

    private func formatUptime(_ seconds: Int?) -> String {
        let value = max(0, seconds ?? 0)
        if value >= 3600 { return "\(value / 3600)h \((value % 3600) / 60)m" }
        if value >= 60 { return "\(value / 60)m \(value % 60)s" }
        return "\(value)s"
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(Color.bgCyan)
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.bgTextPrimary)
            Text(title).font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).bgCard()
    }
}
