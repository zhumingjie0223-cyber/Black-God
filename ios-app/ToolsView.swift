import SwiftUI

struct ToolsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vm: ChatViewModel
    @State private var expression = ""
    @State private var calculation: String?
    @State private var clockResult: String?
    private let starters = [
        ("list.bullet.clipboard", "制定计划", "帮我把下面的目标拆成具体步骤，列出时间安排、依赖和完成标准："),
        ("doc.text.magnifyingglass", "分析与比较", "请比较以下方案，说明评价标准、优缺点和仍需核实的信息："),
        ("square.and.pencil", "写作与改进", "请根据以下用途和读者写一份初稿，再检查结构与遗漏：")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("工作台").font(.bgTitle())
                    Text("一个目标，一步步完成。") .font(.subheadline).foregroundStyle(Color.bgTextSecondary)
                }.padding(.top, 16)
                VStack(alignment: .leading, spacing: 14) {
                    Label("从任务开始", systemImage: "sparkles").font(.bgHeadline()).foregroundStyle(Color.bgGoldLight)
                    ForEach(Array(starters.enumerated()), id: \.offset) { _, item in
                        Button {
                            vm.draft = item.2 + (vm.draft.isEmpty ? "" : "\n" + vm.draft)
                            appState.currentTab = .chat
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.0).frame(width: 26).foregroundStyle(Color.bgGoldLight)
                                Text(item.1).foregroundStyle(Color.bgTextPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(Color.bgTextSecondary)
                            }.padding(.vertical, 9)
                        }
                    }
                }.padding(18).bgCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label("本机计算器", systemImage: "function").font(.bgHeadline()).foregroundStyle(Color.bgGoldLight)
                    Text("直接计算，也可由任务调用；无需 API Key。").font(.caption).foregroundStyle(Color.bgTextSecondary)
                    TextField("例如：(128 + 36) * 1.2", text: $expression)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(12).background(Color.bgCardLight, in: RoundedRectangle(cornerRadius: 12))
                    Button("计算") {
                        calculation = NexusArithmetic.evaluate(expression).map { String(format: "%.12g", $0) } ?? "无法计算，请检查表达式。支持数字、括号及 + − * /。"
                    }.buttonStyle(.borderedProminent).disabled(expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let calculation { Text(calculation).font(.title3.monospacedDigit()).textSelection(.enabled) }
                }.padding(18).bgCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label("日期与时间", systemImage: "clock").font(.bgHeadline()).foregroundStyle(Color.bgGoldLight)
                    Button("读取当前本机时间") {
                        clockResult = Date().formatted(date: .complete, time: .standard) + " · " + TimeZone.current.identifier
                    }
                    if let clockResult { Text(clockResult).font(.subheadline).textSelection(.enabled) }
                }.padding(18).bgCard()
                VStack(alignment: .leading, spacing: 10) {
                    Label("任务能做什么", systemImage: "list.bullet.rectangle").font(.bgHeadline())
                    Text("根据目标制定步骤，使用计算和时钟工具，将结果传回模型继续处理。过程可查看、停止和恢复，最终内容可分享或手动收藏。")
                    Text("目前不具备网页检索、手机系统控制或代你发布应用的能力；模型回答也可能出错。")
                        .foregroundStyle(Color.bgTextSecondary)
                }.font(.caption).padding(.bottom, 18)
            }.padding(.horizontal, 20)
        }
    }
}
