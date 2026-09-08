import SwiftUI

struct NexusLiveExecutionView: View {
    @ObservedObject var live: NexusLiveExecution
    let stop: () -> Void
    @State private var expanded = true
    var body: some View {
        if live.visible {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(live.state == .running ? Color.green : Color.gray).frame(width: 7, height: 7)
                    Text("操作直播").font(.caption.bold())
                    Text(live.state == .running ? "进行中" : "已结束").font(.caption2).foregroundStyle(Color.bgTextSecondary)
                    Spacer()
                    if live.state == .running {
                        Button("停止", action: stop).font(.caption).accessibilityIdentifier("live.stop")
                    }
                    Button(expanded ? "收起" : "展开") { expanded.toggle() }
                        .font(.caption).accessibilityIdentifier("live.expand")
                }
                Text(live.status).font(.caption).lineLimit(2).accessibilityIdentifier("live.status")
                if expanded {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(live.entries) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(label(entry.kind)).foregroundStyle(entry.kind == .error ? Color.orange : Color.bgCyan)
                                            Spacer()
                                            Text(entry.time, style: .time).foregroundStyle(Color.bgTextSecondary)
                                        }.font(.caption2)
                                        Text(entry.text).font(.system(size: 11, design: .monospaced))
                                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    }.id(entry.id)
                                }
                            }.padding(10)
                        }.frame(height: 150).background(Color.black.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("live.screen")
                        .onChange(of: live.entries.last?.id) { _, id in
                            if let id { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                    Text(live.omitted ? "仅显示最近过程；较早内容已省略。" : "显示实际步骤与工具输出；无新输出时保持等待。")
                        .font(.system(size: 10)).foregroundStyle(Color.bgTextSecondary)
                }
            }
            .tint(Color.bgCyan)
            .padding(12).background(Color.bgCard).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.bgCyan.opacity(0.3)))
            .onChange(of: live.state) { _, state in expanded = state == .running }
        }
    }
    private func label(_ kind: NexusLiveExecution.Kind) -> String {
        switch kind {
        case .phase: return "任务步骤"
        case .command: return "操作命令"
        case .output: return "实时输出"
        case .error: return "错误信息"
        case .result: return "工具结果"
        }
    }
}


struct NexusActivityPanel: View {
    @ObservedObject var chat: ChatViewModel
    @ObservedObject var practice: NexusSkillPractice
    var body: some View {
        if practice.isRunning {
            NexusLiveExecutionView(live: practice.live, stop: practice.stop)
        } else {
            NexusLiveExecutionView(live: chat.live, stop: chat.cancel)
        }
    }
}
