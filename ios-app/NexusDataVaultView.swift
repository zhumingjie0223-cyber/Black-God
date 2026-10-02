import SwiftUI

/// 全应用备份导出与危险清空。不包含 API 密钥。
struct NexusDataVaultView: View {
    @ObservedObject var memory: NexusMemoryStore
    @ObservedObject var skills: NexusSkillStore
    var onWiped: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var errorText: String?
    @State private var statusText: String?
    @State private var confirmWipe = false
    @State private var wipePhrase = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("导出会把本机会话、长期记忆与技能名称打成一份 JSON。密钥不在导出中。导入与跨设备同步本轮不做。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("导出全部本地数据") { exportVault() }
                        .accessibilityIdentifier("vault.export")
                }
                Section {
                    Text("清空会删除全部会话与快捷指令任务检查点，并新建一个空对话。长期记忆与技能保留。此操作不可撤销。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("清空全部会话…", role: .destructive) { confirmWipe = true; wipePhrase = "" }
                        .accessibilityIdentifier("vault.wipe")
                }
                if let statusText {
                    Section { Text(statusText).foregroundStyle(Color.bgJadeHi) }
                }
            }
            .navigationTitle("数据与备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .alert("清空全部会话", isPresented: $confirmWipe) {
                TextField("输入「确认删除」", text: $wipePhrase)
                Button("清空", role: .destructive) { wipe() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("请输入「确认删除」四个字后继续。记忆与技能不会被删。")
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .sheet(isPresented: Binding(
                get: { exportURL != nil },
                set: { if !$0 { exportURL = nil } }
            )) {
                if let exportURL {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Text("备份文件已准备好。")
                                .font(.subheadline).foregroundStyle(Color.bgTextSecondary)
                            ShareLink(item: exportURL) {
                                Label("分享备份", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(BGSecondaryButtonStyle())
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bgDark)
                        .navigationTitle("导出")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { self.exportURL = nil } } }
                    }
                    .presentationDetents([.medium])
                }
            }
        }
    }

    private func exportVault() {
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let data = try NexusDataVault(root: root).exportAll(memory: memory.curated, skills: skills.items)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("blackgod-vault.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            statusText = "导出已准备好。"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func wipe() {
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try NexusDataVault(root: root).wipeConversations(confirm: wipePhrase)
            onWiped()
            statusText = "全部会话已清空。"
            confirmWipe = false
        } catch {
            errorText = error.localizedDescription
        }
    }
}
