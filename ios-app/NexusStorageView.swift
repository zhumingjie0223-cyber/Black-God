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
                        LabeledContent("当前硬顶预算", value: size(min(snapshot.budget, NexusStorage.absoluteCeilingGiB * NexusStorage.gib)))
                        LabeledContent("绝对硬顶", value: "\(NexusStorage.absoluteCeilingGiB) GiB")
                        LabeledContent("预算内可增长空间", value: size(snapshot.remaining))
                    }
                    Text("内置执行环境的文件会按需占用手机存储，不预先分配整块磁盘。预算即硬顶：超限拒绝新执行与导入；绝对上限 \(NexusStorage.absoluteCeilingGiB) GiB，不能突破。提高预算可允许继续增长，但不会增加手机的物理容量。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(loading ? "正在读取…" : "刷新空间") { refresh() }.disabled(loading)
                }
                Section("调整空间硬顶") {
                    ForEach(NexusStorage.choices, id: \.self) { value in
                        Button("使用\(value) GiB硬顶") {
                            guard let snapshot else { return }
                            do { try NexusStorage.setBudget(value, snapshot: snapshot); refresh() }
                            catch { self.error = error.localizedDescription }
                        }.disabled(snapshot == nil || loading || value * NexusStorage.gib <= (snapshot?.used ?? 0)).accessibilityIdentifier("storage.budget.\(value)")
                    }
                    Text("执行前硬检查，运行时约每5秒复查并写入客户机上限；至少保留256 MiB手机空间。文件大小为逻辑大小，可能与系统计费占用不同。极端并发下客户机侧仍可能短暂冲高，宿主侧导入与新命令会被硬拒绝。")
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
                let budget = NexusStorage.hardBudget(adoptExistingUsage: measured)
                snapshot = NexusStorageSnapshot(used: measured.used, free: measured.free, budget: budget, files: measured.files)
                error = nil
            }
            catch { self.error = error.localizedDescription }
        }
    }
}
