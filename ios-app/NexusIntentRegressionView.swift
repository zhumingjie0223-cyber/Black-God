import SwiftUI

/// 在设备上运行确定性固定集；不发送内容、不调用模型或执行工具。
struct NexusIntentRegressionView: View {
    @State private var report: NexusIntentRegressionReport?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("50句中文意图回归") {
                    Text("逐项核对对象、工具、澄清和风险。样本是预置开发标签，仍待独立人工审核；一致率不代表真实任务正确率或智慧。")
                        .font(.footnote)
                    Button("运行本地固定集") { run() }
                        .accessibilityIdentifier("intent-regression.run")
                    if let error { Text(error).foregroundStyle(.orange) }
                }
                if let report {
                    Section("本次结果") {
                        Text("全部条件一致：\(report.exactCorrect)/\(report.total)")
                            .accessibilityIdentifier("intent-regression.score")
                        Text("对象：\(report.objectCorrect)/\(report.total)")
                        Text("工具：\(report.toolCorrect)/\(report.total)")
                        Text("澄清：\(report.clarificationCorrect)/\(report.total)")
                        Text("风险：\(report.riskCorrect)/\(report.total)")
                        Text(report.labelStatus).font(.footnote)
                    }
                    Section("逐句结果") {
                        ForEach(report.observations) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.goal)
                                Text(item.passed ? "与预置标签一致" : item.issues.joined(separator: "；"))
                                    .font(.caption).foregroundStyle(item.passed ? Color.secondary : Color.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("意图固定回归")
        }
    }

    private func run() {
        do {
            guard let url = Bundle.main.url(forResource: "nexus-intent-50", withExtension: "json") else {
                throw NexusReasoningError.execution("应用未包含50句固定集资源，请检查构建配置。")
            }
            report = try NexusIntentRegression.evaluate(data: Data(contentsOf: url))
            error = nil
        } catch { report = nil; self.error = error.localizedDescription }
    }
}
