import SwiftUI

struct NexusLiveExecutionView: View {
    @ObservedObject var live: NexusLiveExecution
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let stop: () -> Void
    @State private var expanded = true
    @ScaledMetric(relativeTo: .caption) private var screenHeight = 150.0

    var body: some View {
        if live.visible {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        heading
                        Spacer(minLength: 0)
                        controls
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        heading
                        controls
                    }
                }
                Text(live.status)
                    .font(.subheadline).foregroundStyle(Color.bgTextPrimary)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("live.status")
                if expanded {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if live.entries.isEmpty {
                                    Text("等待新的执行记录…")
                                        .font(.caption).foregroundStyle(Color.bgTextSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                ForEach(live.entries) { entry in
                                    eventRow(entry).id(entry.id)
                                }
                            }.padding(12)
                        }
                        .frame(height: min(screenHeight, 280))
                        .background(Color.bgDark.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("live.screen")
                        .onChange(of: live.entries.last?.id) { _, id in
                            if let id { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                    Text(live.omitted ? "显示最近 \(live.entries.count) 条记录，较早内容已省略。" : "显示实际步骤与工具输出；没有新输出时保持等待。")
                        .font(.caption2).foregroundStyle(Color.bgTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.bgJadeHi)
            .frame(maxWidth: .infinity, alignment: .leading).bgCard()
            .onChange(of: live.state) { _, state in expanded = state == .running }
        }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: stateSymbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(stateColor)
                .frame(width: 32, height: 32)
                .background(stateColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("执行过程").font(.subheadline.weight(.semibold)).foregroundStyle(Color.bgTextPrimary)
                Text(stateLabel).font(.caption).foregroundStyle(stateColor)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if live.state == .running {
                Button(role: .destructive, action: stop) {
                    Label("停止", systemImage: "stop.fill").foregroundStyle(Color.orange)
                }
                .buttonStyle(BGSecondaryButtonStyle())
                .accessibilityIdentifier("live.stop")
            }
            Button { expanded.toggle() } label: {
                Label(expanded ? "收起" : "展开", systemImage: expanded ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(BGSecondaryButtonStyle())
            .accessibilityIdentifier("live.expand")
            .accessibilityValue(expanded ? "已展开" : "已收起")
        }.font(.caption.weight(.semibold))
    }

    private func eventRow(_ entry: NexusLiveExecution.Entry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label(entry.kind)).foregroundStyle(entry.kind == .error ? Color.orange : Color.bgJadeHi)
                Spacer(minLength: 0)
                Text(entry.time, style: .time).monospacedDigit().foregroundStyle(Color.bgTextSecondary)
            }.font(.caption2.weight(.medium))
            Text(entry.text)
                .font(.system(.caption, design: .monospaced)).foregroundStyle(Color.bgTextPrimary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stateLabel: String {
        switch live.state {
        case .idle: return "等待开始"
        case .running: return "执行中"
        case .answered: return "答复已生成"
        case .warning: return "存在警告"
        case .failed: return "执行失败"
        case .cancelled: return "已停止"
        }
    }

    private var stateSymbol: String {
        switch live.state {
        case .idle: return "circle.dotted"
        case .running: return "waveform"
        case .answered: return "text.bubble"
        case .warning: return "exclamationmark.triangle"
        case .failed: return "xmark.circle"
        case .cancelled: return "pause"
        }
    }

    private var stateColor: Color {
        switch live.state {
        case .running, .answered: return .bgJadeHi
        case .warning, .failed: return .orange
        case .idle, .cancelled: return .bgTextSecondary
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

/// Running shell tools get a compact live window; other work stays in a single status row.
struct NexusActivitySummary: View {
    @ObservedObject var chat: ChatViewModel
    @ObservedObject var practice: NexusSkillPractice
    let openDetails: () -> Void

    var body: some View {
        if practice.isRunning {
            NexusRunningActivitySummaryRow(live: practice.live, openDetails: openDetails, stop: practice.stop)
        } else {
            NexusRunningActivitySummaryRow(live: chat.live, openDetails: openDetails, stop: chat.cancel)
        }
    }
}

private struct NexusRunningActivitySummaryRow: View {
    @ObservedObject var live: NexusLiveExecution
    let openDetails: () -> Void
    let stop: () -> Void
    @ScaledMetric(relativeTo: .caption) private var shellOutputHeight = 108.0

    private var shellEntries: [NexusLiveExecution.Entry] {
        guard let command = live.latestCommand else { return [] }
        let start = live.entries.firstIndex(where: { $0.id == command.id }).map { $0 + 1 } ?? 0
        return [command] + live.entries.dropFirst(start).filter {
            $0.kind == .output || $0.kind == .error || $0.kind == .result
        }
    }

    var body: some View {
        if live.state == .running {
            if !shellEntries.isEmpty {
                VStack(spacing: 0) {
                    header(shell: true)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(shellEntries) { entry in
                                    Text((entry.kind == .command ? "$ " : "") + entry.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(entry.kind == .error ? Color.orange : entry.kind == .command ? Color.bgJadeHi : Color.bgTextPrimary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(entry.id)
                                }
                            }.padding(10)
                        }
                        .frame(height: min(shellOutputHeight, 220))
                        .background(Color.bgDark, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("chat.shellOutput")
                        .onAppear {
                            if let id = shellEntries.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                        }
                        .onChange(of: shellEntries.last?.id) { _, id in
                            if let id { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 8)
                }
                .bgFloating(cornerRadius: 18)
                .accessibilityIdentifier("chat.shellLive")
            } else {
                header(shell: false).bgFloating(cornerRadius: 18)
            }
        }
    }

    private func header(shell: Bool) -> some View {
        HStack(spacing: 0) {
            Button(action: openDetails) {
                HStack(spacing: 0) {
                    Image(systemName: shell ? "terminal" : "waveform")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Color.bgJadeHi)
                        .frame(width: shell ? 36 : 44).accessibilityHidden(true)
                    if shell {
                        Text("工具直播").font(.caption.weight(.semibold)).foregroundStyle(Color.bgJadeHi)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false).padding(.trailing, 8)
                    }
                    Text(live.status)
                        .font(shell ? .caption : .subheadline).foregroundStyle(Color.bgTextPrimary)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Color.bgTextSecondary)
                        .frame(width: 24).accessibilityHidden(true)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shell ? "工具直播详情" : "任务详情")
            .accessibilityValue(live.status)
            .accessibilityHint("查看当前任务的完整执行记录")
            .accessibilityIdentifier("chat.taskDetails")

            Rectangle().fill(Color.bgTextSecondary.opacity(0.18)).frame(width: 1, height: 18)
                .accessibilityHidden(true)

            Button(role: .destructive, action: stop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.orange)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停止当前任务")
            .accessibilityIdentifier("chat.taskStop")
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
