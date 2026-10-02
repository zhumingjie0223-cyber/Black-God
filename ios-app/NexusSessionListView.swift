import SwiftUI

/// 会话列表：新建、切换、重命名、删除、导出、跨会话检索。长期记忆与技能不在此管理。
struct NexusSessionListView: View {
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var renameTarget: NexusSessionRecord?
    @State private var renameText = ""
    @State private var deleteTarget: NexusSessionRecord?
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var query = ""
    @State private var hits: [NexusSessionLibrary.SearchHit] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if vm.createSession() { dismiss() }
                    } label: {
                        Label("新建对话", systemImage: "plus.message")
                    }
                    .accessibilityIdentifier("sessions.create")
                }
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("检索结果") {
                        if hits.isEmpty {
                            Text("没有匹配的消息。").foregroundStyle(Color.bgTextSecondary)
                        } else {
                            ForEach(hits) { hit in
                                Button {
                                    if vm.switchSession(hit.sessionID) { dismiss() }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(hit.sessionTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Color.bgTextPrimary)
                                        Text((hit.role == "user" ? "你：" : "Black God：") + hit.snippet)
                                            .font(.caption).foregroundStyle(Color.bgTextSecondary).lineLimit(3)
                                    }
                                }
                                .accessibilityIdentifier("sessions.hit.\(hit.messageID.uuidString)")
                            }
                        }
                    }
                }
                Section {
                    ForEach(vm.sessions) { session in
                        Button {
                            if vm.switchSession(session.id) { dismiss() }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Color.bgTextPrimary)
                                        .lineLimit(2)
                                    Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(Color.bgTextSecondary)
                                }
                                Spacer(minLength: 8)
                                if session.id == vm.activeSessionID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.bgJadeHi)
                                        .accessibilityLabel("当前会话")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sessions.item.\(session.id.uuidString)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", role: .destructive) { deleteTarget = session }
                                .disabled(vm.sessions.count <= 1)
                            Button("重命名") {
                                renameTarget = session
                                renameText = session.title
                            }
                        }
                        .contextMenu {
                            Button("重命名") {
                                renameTarget = session
                                renameText = session.title
                            }
                            Button("导出 JSON") { export(session.id, plain: false) }
                            Button("导出文本") { export(session.id, plain: true) }
                            if vm.sessions.count > 1 {
                                Button("删除", role: .destructive) { deleteTarget = session }
                            }
                        }
                    }
                } footer: {
                    Text("每个会话的聊天与任务恢复互相隔离。长期记忆、技能与自我状态仍跨会话共享。最多 \(NexusSessionLibrary.maxSessions) 个会话。可在上方搜索跨会话内容。")
                }
            }
            .searchable(text: $query, prompt: "搜索全部会话")
            .onChange(of: query) { _, value in
                hits = (try? vm.searchSessions(value)) ?? []
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgDark)
            .navigationTitle("会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("导出当前") {
                        if let id = vm.activeSessionID { export(id, plain: false) }
                    }
                    .disabled(vm.activeSessionID == nil)
                    .accessibilityIdentifier("sessions.exportActive")
                }
            }
            .alert("重命名会话", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("标题", text: $renameText)
                Button("保存") {
                    if let target = renameTarget {
                        _ = vm.renameSession(target.id, title: renameText)
                    }
                    renameTarget = nil
                }
                Button("取消", role: .cancel) { renameTarget = nil }
            }
            .confirmationDialog("删除此会话？", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ), titleVisibility: .visible) {
                Button("删除会话", role: .destructive) {
                    if let target = deleteTarget {
                        _ = vm.deleteSession(target.id)
                    }
                    deleteTarget = nil
                }
                Button("取消", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("将永久删除该会话的聊天消息与任务恢复记录，无法撤销。长期记忆与技能不受影响。")
            }
            .alert("导出失败", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("好", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .sheet(isPresented: Binding(
                get: { exportURL != nil },
                set: { if !$0 { exportURL = nil } }
            )) {
                if let exportURL {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Text("导出文件已准备好，可通过系统分享发送或保存。")
                                .font(.subheadline)
                                .foregroundStyle(Color.bgTextSecondary)
                                .multilineTextAlignment(.center)
                            ShareLink(item: exportURL) {
                                Label("分享导出文件", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(BGSecondaryButtonStyle())
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bgDark)
                        .navigationTitle("导出")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { self.exportURL = nil }
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
            }
        }
    }

    private func export(_ id: UUID, plain: Bool) {
        do {
            let data: Data
            let name: String
            let sessionTitle = vm.sessions.first(where: { $0.id == id })?.title ?? "会话"
            let safe = sessionTitle.replacingOccurrences(of: "/", with: "-")
            if plain {
                data = Data(try vm.exportSessionText(id).utf8)
                name = "\(safe).md"
            } else {
                data = try vm.exportSessionJSON(id)
                name = "\(safe).json"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportError = error.localizedDescription
        }
    }
}
