import SwiftUI

struct MonitorView: View {
    @EnvironmentObject var vm: ChatViewModel
    var body: some View { NexusHistoryList(store: vm.history) }
}

struct NexusHistoryList: View {
    @ObservedObject var store: NexusTaskHistoryStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("本机任务记录", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text("\(store.records.count) / 50").foregroundStyle(Color.bgGoldLight)
                    }
                    Text("保留最近 50 次任务。左滑删除，点击查看计划、工具记录和最终结果。删除记录不清空当前对话；对话页可选择新对话。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.records.isEmpty {
                    ContentUnavailableView("还没有任务记录", systemImage: "tray", description: Text("完成或停止一次任务后，结果会保存在这里。"))
                }
                ForEach(store.records) { record in
                    NavigationLink {
                        NexusHistoryDetail(record: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(record.goal).lineLimit(2).foregroundStyle(Color.bgTextPrimary)
                            HStack {
                                Text(record.status.displayName).foregroundStyle(record.status == .completed ? Color.bgGoldLight : Color.orange)
                                Spacer()
                                Text(record.updatedAt, style: .date).foregroundStyle(.secondary)
                            }.font(.caption)
                        }.padding(.vertical, 4)
                    }
                    .swipeActions { Button("删除", role: .destructive) { store.remove(record.id) } }
                }
                if let error = store.lastError { Text(error).foregroundStyle(.orange).font(.caption) }
            }
            .scrollContentBackground(.hidden).background(Color.bgDark)
            .navigationTitle("记录")
        }
    }
}

private struct NexusHistoryDetail: View {
    let record: NexusTaskHistoryRecord
    var body: some View {
        List {
            Section("任务") { Text(record.goal).textSelection(.enabled); Text("\(record.model) · \(record.status.displayName)").font(.caption).foregroundStyle(.secondary) }
            if let plan = record.plan {
                Section("步骤") {
                    ForEach(plan.steps) { step in
                        DisclosureGroup {
                            Text(step.result ?? "无输出").font(.caption).textSelection(.enabled)
                        } label: { Label(step.title, systemImage: step.status.symbol) }
                    }
                }
            }
            if !record.toolTraces.isEmpty {
                Section("工具结果") {
                    ForEach(record.toolTraces) { trace in
                        DisclosureGroup("\(trace.name) · \(trace.succeeded ? "完成" : "失败")") { Text(trace.result).font(.caption).textSelection(.enabled) }
                    }
                }
            }
            Section("结果") { Text(record.result).textSelection(.enabled) }
            Section { ShareLink(item: "# \(record.goal)\n\n\(record.result)") { Label("分享结果", systemImage: "square.and.arrow.up") } }
        }.scrollContentBackground(.hidden).background(Color.bgDark)
            .navigationTitle("任务详情").navigationBarTitleDisplayMode(.inline)
    }
}

extension NexusTaskHistoryStatus {
    var displayName: String {
        switch self {
        case .completed: return "流程完成"
        case .failed: return "未完成"
        case .cancelled: return "已停止"
        }
    }
}
