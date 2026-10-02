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
                Text("执行剧场").font(.subheadline.weight(.semibold)).foregroundStyle(Color.bgTextPrimary)
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openDetails: () -> Void
    let stop: () -> Void
    @State private var pulse = false
    @ScaledMetric(relativeTo: .caption) private var shellOutputHeight = 128.0

    private var shellEntries: [NexusLiveExecution.Entry] {
        guard let command = live.latestCommand else { return [] }
        let start = live.entries.firstIndex(where: { $0.id == command.id }).map { $0 + 1 } ?? 0
        return [command] + live.entries.dropFirst(start).filter {
            $0.kind == .output || $0.kind == .error || $0.kind == .result
        }
    }

    var body: some View {
        if live.state == .running {
            VStack(spacing: 0) {
                header(shell: !shellEntries.isEmpty)
                if !shellEntries.isEmpty {
                    theaterScreen
                } else {
                    progressRail
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .bgFloating(cornerRadius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.bgJadeHi.opacity(pulse ? 0.55 : 0.18), lineWidth: 1.2)
            )
            .shadow(color: Color.bgJadeHi.opacity(pulse ? 0.18 : 0.05), radius: pulse ? 18 : 8)
            .accessibilityIdentifier(shellEntries.isEmpty ? "chat.taskLive" : "chat.shellLive")
            .onAppear {
                guard !reduceMotion, ChatMotion.continuousAnimationsEnabled else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            }
            .onChange(of: live.entries.count) { _, count in
                // 每步轻触；UI 测关闭连续动效时也不打满震动
                guard ChatMotion.continuousAnimationsEnabled, appState.hapticEnabled, count > 0 else { return }
                appState.haptic(.soft)
            }
        }
    }

    private var theaterScreen: some View {
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
                }.padding(12)
            }
            .frame(height: min(shellOutputHeight, 240))
            .background(
                LinearGradient(
                    colors: [Color.bgDark, Color(red: 0.03, green: 0.07, blue: 0.05)],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.bgJadeHi.opacity(0.12), lineWidth: 1)
            )
            .accessibilityIdentifier("chat.shellOutput")
            .onAppear {
                if let id = shellEntries.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .onChange(of: shellEntries.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var progressRail: some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(Color.bgJadeHi.opacity(pulse ? (i % 2 == 0 ? 0.55 : 0.22) : 0.2))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func header(shell: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                appState.haptic(.light)
                openDetails()
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: shell ? "terminal.fill" : "sparkle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.bgJadeHi)
                        .frame(width: shell ? 36 : 44).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shell ? "执行剧场 · 直播" : "执行剧场")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.bgJadeHi)
                            .lineLimit(1)
                        Text(live.status)
                            .font(.caption)
                            .foregroundStyle(Color.bgTextPrimary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
                    Text("\(live.entries.count)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.bgJadeHi)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.bgJadeHi.opacity(0.12), in: Capsule())
                        .accessibilityLabel("已记录 \(live.entries.count) 步")
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold)).foregroundStyle(Color.bgTextSecondary)
                        .frame(width: 22).accessibilityHidden(true)
                }.frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shell ? "拉开执行剧场直播" : "拉开执行剧场")
            .accessibilityValue(live.status)
            .accessibilityHint("查看当前任务的完整执行记录")
            .accessibilityIdentifier("chat.taskDetails")

            Rectangle().fill(Color.bgTextSecondary.opacity(0.18)).frame(width: 1, height: 22)
                .accessibilityHidden(true)

            Button(role: .destructive, action: stop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.orange)
                    .frame(width: 44, height: 52).contentShape(Rectangle())
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
