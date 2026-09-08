import SwiftUI

struct NexusStorageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: NexusStorageSnapshot?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            List {
                Section("内置空间") {
                    if let snapshot {
                        LabeledContent("运行环境文件大小", value: size(snapshot.used))
                        LabeledContent("手机剩余空间", value: size(snapshot.free))
                        LabeledContent("当前使用预算", value: size(snapshot.budget))
                        LabeledContent("预算内可增长空间", value: size(snapshot.remaining))
                    }
                    Text("iSH文件会按需占用手机存储，不预先分配整块磁盘。提高预算可允许继续增长，但不会增加手机的物理容量。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(loading ? "正在读取…" : "刷新空间") { refresh() }.disabled(loading)
                }
                Section("调整空间预算") {
                    ForEach(NexusStorage.choices, id: \.self) { value in
                        Button("使用\(value) GiB预算") {
                            guard let snapshot else { return }
                            do { try NexusStorage.setBudget(value, snapshot: snapshot); refresh() }
                            catch { self.error = error.localizedDescription }
                        }.disabled(snapshot == nil || loading || value * NexusStorage.gib <= (snapshot?.used ?? 0)).accessibilityIdentifier("storage.budget.\(value)")
                    }
                    Text("执行前检查，运行时约每5秒复查；至少保留256 MiB手机空间。它是监测预算，快速写入可能短暂超过，尚非文件系统硬配额。文件大小为逻辑大小，可能与系统计费占用不同。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .tint(Color.bgCyan)
            .navigationTitle("运行空间")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { refresh() }
        }
    }
    private func size(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .binary) }
    private func refresh() {
        guard !loading else { return }; loading = true
        Task {
            defer { loading = false }
            do {
                let measured = try await Task.detached(priority: .utility) { try NexusStorage.measure() }.value
                let budget = NexusStorage.adoptExistingUsage(measured)
                snapshot = NexusStorageSnapshot(used: measured.used, free: measured.free, budget: budget, files: measured.files)
                error = nil
            }
            catch { self.error = error.localizedDescription }
        }
    }
}
