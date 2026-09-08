import SwiftUI

struct NexusSkillDraft: Identifiable {
    let id = UUID()
    var skill: NexusSkill? = nil
    var source: NexusAgentCheckpoint? = nil
}

struct NexusSkillsView: View {
    @ObservedObject var store: NexusSkillStore
    @ObservedObject var practice: NexusSkillPractice
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NexusSkillDraft?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("保存可重复使用的流程。模型会先查看名称和适用条件，需要时再读取步骤；每次仍需验证结果。")
                    Text("技能不是已经验证的能力。目录和被读取的内容会发给当前模型，不要保存密钥。删除后，旧聊天和任务记录仍保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = error ?? store.lastError {
                    Section { Text(error).foregroundStyle(.red); Button("重新读取") { store.reload(); self.error = nil } }
                }
                Section("用户技能 · \(store.items.count)/\(NexusSkillStore.maximumItems)") {
                    ForEach(store.items) { skill in
                        Button { draft = NexusSkillDraft(skill: skill) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(skill.current.content.name).font(.headline)
                                Text(skill.current.content.applicability).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text("版本 \(skill.current.number) · 用户整理，需验证").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.swipeActions {
                            Button("删除", role: .destructive) {
                                do { try store.remove(skill.id) } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                    Button("添加技能") { draft = NexusSkillDraft() }.accessibilityIdentifier("skills.add")
                }
                Section("内置技能与自动演练") {
                    Toggle("闲置时自动演练", isOn: $practice.automatic).accessibilityIdentifier("practice.auto")
                    Text("仅在应用前台、聊天闲置时每15分钟最多演练一轮；使用隔离的合成样例，无模型API费用。进入后台或开始聊天会停止。相同版本至少通过3轮才显示已巩固；不代表训练了模型。")
                        .font(.caption).foregroundStyle(.secondary)
                    if practice.isRunning {
                        Text(practice.current)
                        Button("停止演练", role: .destructive) { practice.stop() }.accessibilityIdentifier("practice.stop")
                    } else {
                        Button("立即演练内置技能") { practice.start() }.accessibilityIdentifier("practice.start")
                    }
                    if let error = practice.lastError { Text(error).foregroundStyle(.red) }
                    ForEach(NexusBuiltinSkills.all) { item in
                        DisclosureGroup(item.skill.current.content.name + (item.missing == nil ? "" : " · 待接入")) {
                            Text(item.source).font(.caption)
                            Text(item.skill.current.content.steps).font(.caption)
                            Text(practice.label(item)).font(.caption)
                            Text(item.skill.current.content.verification).font(.caption)
                        }
                    }
                    if let round = practice.rounds.last {
                        Text("最近演练：\(round.results.filter(\.passed).count)/\(round.results.count)个样例通过 · \(round.state == "completed" ? "本轮结束" : round.state == "running" ? "进行中" : "已中断")").font(.caption)
                        ForEach(round.results.filter { !$0.passed }) { result in
                            Text("\(result.title)：\(result.evidence)").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

            }
            .tint(Color.bgCyan)
            .navigationTitle("任务技能")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $draft) { draft in NexusSkillEditor(store: store, draft: draft) }
        }
    }
}

struct NexusSkillEditor: View {
    @ObservedObject var store: NexusSkillStore
    let draft: NexusSkillDraft
    @Environment(\.dismiss) private var dismiss
    @State private var content: NexusSkillContent
    @State private var error: String?

    init(store: NexusSkillStore, draft: NexusSkillDraft) {
        self.store = store
        self.draft = draft
        _content = State(initialValue: draft.skill?.current.content ?? draft.source.flatMap(NexusSkillContent.candidate) ?? .empty)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("名称") { TextField("例如：核对订单总价", text: $content.name).accessibilityIdentifier("skills.name") }
                Section("适用条件") { TextField("何时适合用这个流程", text: $content.applicability, axis: .vertical).accessibilityIdentifier("skills.conditions") }
                Section("操作步骤") { TextEditor(text: $content.steps).frame(minHeight: 110).accessibilityIdentifier("skills.steps") }
                Section("验收方法") { TextField("如何检查结果是否正确", text: $content.verification, axis: .vertical).accessibilityIdentifier("skills.verification") }
                Section {
                    Text(draft.source != nil ? "这些步骤来自一次任务记录，请检查并补全适用条件；不会复制原始工具参数或脚本。" : "保存的是流程参考。适用条件和验收方法必须填写，模型不能据此声称任务已经完成。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if let skill = draft.skill {
                    if !skill.history.isEmpty {
                        Section("历史版本（最多保留5个）") {
                            ForEach(skill.history) { revision in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("版本 \(revision.number)：\(revision.content.name)").font(.headline)
                                    Text(revision.content.steps).font(.caption).lineLimit(3)
                                    Button("恢复版本 \(revision.number)") {
                                        do { try store.restore(skillID: skill.id, revisionID: revision.id); dismiss() }
                                        catch { self.error = error.localizedDescription }
                                    }.accessibilityIdentifier("skills.restore.\(revision.number)")
                                }
                            }
                        }
                    }
                    Button("删除技能", role: .destructive) {
                        do { try store.remove(skill.id); dismiss() } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("skills.delete")
                }
            }
            .navigationTitle(draft.skill == nil ? "保存任务技能" : "编辑任务技能")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try store.save(content, replacing: draft.skill?.id, source: draft.source); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("skills.save")
                }
            }
        }
    }
}
