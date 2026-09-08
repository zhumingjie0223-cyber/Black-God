import SwiftUI

struct NexusMemoryView: View {
    @ObservedObject var store: NexusMemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("你决定神枢记住什么。相关记忆会在执行任务时发送给已授权的 AI 服务商。删除后这条收藏不再作为记忆传送。对话和历史中的副本需另行清理：对话页选择新对话，记录页左滑删除。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("添加记忆") {
                    TextField("偏好、背景或希望记住的信息…", text: $draft, axis: .vertical).lineLimit(2...5)
                    Button("保存记忆") {
                        if store.remember(draft, kind: "saved", source: "user", confidence: 1) { draft = "" }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 4000)
                    Text("\(draft.count) / 4000 字").font(.caption).foregroundStyle(.secondary)
                }
                Section("已收藏 · \(store.items.count) / 200") {
                    ForEach(store.items.reversed().filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.text).textSelection(.enabled)
                            Text(item.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("删除", role: .destructive) { store.remove(item.id) } }
                    }
                    if store.items.isEmpty { Text("暂未保存记忆").foregroundStyle(.secondary) }
                }
                if let error = store.lastError { Text(error).foregroundStyle(.orange) }
            }.scrollContentBackground(.hidden).background(Color.bgDark)
                .searchable(text: $query, prompt: "搜索已收藏记忆")
                .navigationTitle("记忆")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
