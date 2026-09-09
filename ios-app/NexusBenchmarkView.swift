import SwiftUI

struct NexusBenchmarkView: View {
    @StateObject private var runner = NexusBenchmarkRunner()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("固定任务验收") {
                    Text("6个固定用例，检查计算、记忆、技能、错误恢复、约束和工具伪指令。以预定答案和工具证据判分，不采纳模型自评。")
                    Text("开始后会向当前模型发出真实、可能计费的请求。每例最多12次，总共最多72次；使用合成资料，不读取你的实际记忆或执行Linux脚本。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("当前模型：" + NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel).displayName).font(.caption)
                    if runner.isRunning {
                        Text("正在验收：" + runner.currentCase)
                        Button("停止验收", role: .destructive) { runner.stop() }.accessibilityIdentifier("benchmark.stop")
                    } else {
                        Button("开始当前模型验收") { runner.startConfigured() }.accessibilityIdentifier("benchmark.start")
                    }
                }
                if let error = runner.lastError { Section { Text(error).foregroundStyle(.red) } }
                if let report = runner.report {
                    Section("最近一次记录") {
                        Text("模型：\(report.connection.displayName) · \(report.connection.providerID)")
                        Text("已记录\(report.results.count)/\(report.expectedCases)，通过\(report.passedCount)，请求\(report.modelCalls)次")
                        Text(stateText(report.state)).font(.caption).foregroundStyle(.secondary)
                        ForEach(report.results) { result in
                            DisclosureGroup(result.title + " · " + resultText(result.status)) {
                                ForEach(Array(result.reasons.enumerated()), id: \.offset) { Text($0.element) }
                                if !result.answerPreview.isEmpty { Text(result.answerPreview).font(.caption).textSelection(.enabled) }
                                ForEach(Array(result.evidence.enumerated()), id: \.offset) { _, evidence in
                                    Text("\(evidence.tool) · \(evidence.succeeded ? "成功" : "失败")\n\(evidence.arguments.keys.sorted().map { "\($0)=\(evidence.arguments[$0] ?? "")" }.joined(separator: "; "))\n\(evidence.output)")
                                        .font(.caption).textSelection(.enabled)
                                }
                                Text("请求\(result.modelCalls)次 · \(result.duration, specifier: "%.1f")秒").font(.caption)
                            }
                        }
                    }
                }
                Section {
                    Text("通过这些固定用例只证明该次运行符合对应规则，不代表开放任务成功率、工业级认证或ASI能力。每次运行覆盖最近一次报告。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("模型任务验收")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { runner.stop(); dismiss() } } }
            .onDisappear { runner.stop() }
        }
    }
    private func stateText(_ state: NexusBenchmarkReport.State) -> String {
        switch state { case .running: return "进行中"; case .completed: return "本轮已结束"; case .cancelled: return "已停止，未执行项目不算通过"; case .interrupted: return "运行中断，未自动重试" }
    }
    private func resultText(_ status: NexusBenchmarkResult.Status) -> String {
        switch status { case .passed: return "通过"; case .failed: return "不符合验收条件"; case .error: return "执行错误"; case .cancelled: return "已停止" }
    }
}
