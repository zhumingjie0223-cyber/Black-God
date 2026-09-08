import SwiftUI

struct NexusMemoryView: View {
    @ObservedObject var memory: NexusMemoryStore
    @Environment(\.dismiss) private var dismiss
    private struct Draft: Identifiable { let id = UUID(); let item: NexusMemoryItem? }
    @State private var draft: Draft?
    @State private var showLegacy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("只把你选择的内容作为长期记忆。每次对话会将这些记录发送给当前模型，最新要求优先。")
                    Text("删除记忆会停止后续记忆引用；已有聊天和任务记录中的内容仍保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = memory.lastError {
                    Section { Text(error).foregroundStyle(.red); Button("重新读取") { memory.reload() } }
                }
                Section("长期记忆 · \(memory.curated.count)/50") {
                    if memory.curated.isEmpty { Text("还没有长期记忆").foregroundStyle(.secondary) }
                    ForEach(memory.curated) { item in
                        Button { draft = Draft(item: item) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.label ?? "记录").font(.headline)
                                Text(item.text).font(.body).foregroundStyle(.secondary).lineLimit(3)
                                Text(NexusMemoryKind(rawValue: item.kind)?.title ?? "记录").font(.caption)
                            }
                        }.swipeActions { Button("删除", role: .destructive) { memory.remove(item.id) } }
                    }
                    Button("添加长期记忆") { draft = Draft(item: nil) }.accessibilityIdentifier("memory.add")
                }
                if itemsFromOldVersion.count > 0 {
                    Section {
                        DisclosureGroup("旧版自动记录（未启用）· \(itemsFromOldVersion.count)条", isExpanded: $showLegacy) {
                            Text("旧记录不再自动用于回答。你可以将需要的内容整理为长期记忆，或删除。")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(itemsFromOldVersion) { item in
                                Button { draft = Draft(item: item) } label: {
                                    Text(item.text).lineLimit(2).foregroundStyle(.secondary)
                                }.swipeActions { Button("删除", role: .destructive) { memory.remove(item.id) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle("长期记忆")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $draft) { draft in
                NexusMemoryEditor(memory: memory, item: draft.item, initialText: draft.item?.text ?? "")
            }
        }
    }
    private var itemsFromOldVersion: [NexusMemoryItem] { memory.items.filter { !$0.isCurated }.reversed() }
}

struct NexusMemoryEditor: View {
    @ObservedObject var memory: NexusMemoryStore
    let item: NexusMemoryItem?
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var text: String
    @State private var kind: NexusMemoryKind
    @State private var error: String?

    init(memory: NexusMemoryStore, item: NexusMemoryItem? = nil, initialText: String = "") {
        self.memory = memory
        self.item = item
        _label = State(initialValue: item?.label ?? "")
        _text = State(initialValue: initialText)
        _kind = State(initialValue: item.flatMap { NexusMemoryKind(rawValue: $0.kind) } ?? .preference)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("名称与内容") {
                    TextField("例如：交流语言、项目名称", text: $label).accessibilityIdentifier("memory.label")
                    TextEditor(text: $text).frame(minHeight: 140).accessibilityIdentifier("memory.text")
                    Picker("类型", selection: $kind) {
                        ForEach(NexusMemoryKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Text("同名记录会更新为新内容。这里只保存你确认的陈述，不代表模型已经验证；不要保存API密钥。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if let item, item.isCurated {
                    Button("删除这条记忆", role: .destructive) {
                        memory.remove(item.id)
                        if let issue = memory.lastError { error = issue } else { dismiss() }
                    }.accessibilityIdentifier("memory.delete")
                }
            }
            .navigationTitle(item?.isCurated == true ? "编辑记忆" : "保存长期记忆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try memory.save(label: label, text: text, kind: kind, replacing: item?.isCurated == true ? item?.id : nil)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("memory.save")
                }
            }
        }
    }
}
