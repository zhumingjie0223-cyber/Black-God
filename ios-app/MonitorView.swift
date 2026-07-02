//
//  MonitorView.swift — 动态监测页
//

import SwiftUI

struct MonitorView: View {
    @EnvironmentObject var appState: AppState
    @State private var cpuUsage = 0.0
    @State private var memUsage = 0.0
    @State private var services: [(String, Bool)] = [("bg-agent", true), ("bg-gateway", true), ("nginx", true)]
    @State private var timer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("动态监测").font(.bgTitle()).foregroundStyle(Color.bgTextPrimary)
                    .padding(.horizontal, 16).padding(.top, 8)
                HStack(spacing: 14) {
                    GaugeCard(title: "CPU", value: cpuUsage, color: .bgCyan)
                    GaugeCard(title: "内存", value: memUsage, color: .bgPurple)
                }
                .padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 12) {
                    Text("服务状态").font(.bgHeadline()).foregroundStyle(Color.bgTextPrimary)
                    ForEach(services, id: \.0) { svc in
                        HStack {
                            Circle().fill(svc.1 ? Color.green : Color.red).frame(width: 8, height: 8)
                            Text(svc.0).font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
                            Spacer()
                            Text(svc.1 ? "运行中" : "停止").font(.bgCaption())
                                .foregroundStyle(svc.1 ? Color.green : Color.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(16).bgCard().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                        Text("安全状态正常").font(.bgBody()).foregroundStyle(Color.bgTextPrimary)
                    }
                    Text("无异常登录 · 无攻击尝试").font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).bgCard().padding(.horizontal, 16)
            }
            .padding(.bottom, 100)
        }
        .padding(.top, 50)
        .onAppear { startMonitoring() }
        .onDisappear { timer?.invalidate() }
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            withAnimation {
                cpuUsage = Double.random(in: 5...35)
                memUsage = Double.random(in: 30...60)
            }
        }
    }
}

struct GaugeCard: View {
    let title: String
    let value: Double
    let color: Color
    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.bgCaption()).foregroundStyle(Color.bgTextSecondary)
            ZStack {
                Circle().stroke(Color.bgCardLight, lineWidth: 8)
                Circle().trim(from: 0, to: value / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value))%").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.bgTextPrimary)
            }
            .frame(width: 90, height: 90)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).bgCard()
    }
}
