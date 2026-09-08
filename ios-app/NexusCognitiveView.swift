import SwiftUI
import PhotosUI

struct NexusCognitiveView: View {
    @ObservedObject var control: NexusCognitiveControl
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var recognizing = false
    @State private var observation: String?
    @State private var topic = ""
    @State private var statement = ""
    @State private var source = ""
    @State private var message: String?
    private func perform(_ action: () throws -> Void) { do { try action(); message = nil } catch { message = error.localizedDescription } }
    var body: some View {
        NavigationStack {
            Form {
                Section("自我状态") {
                    NavigationLink("查看自我状态流") { NexusSelfContinuityView(stream: control.continuity) }.accessibilityIdentifier("self.open")
                }
                Section("可验证的自我检查") {
                    Text("记录已知资料、来源、错误和工具结果。不会宣称具有主观意识，也不会自行改写模型权重或提升权限。")
                    Text("数学：计算工具\n因果：给定线性模型的干预计算\n长期规划：依赖检查、时长下界和任务检查点\n科学发现：可辅助提出假设，仍需外部证据与真实实验验证。")
                }
                Section("模型工具权限") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(control.state.stopped ? "已停止" : (control.state.workspaceUntil.map { $0 > context.date } ?? false) ? "工作区授权至 \(control.state.workspaceUntil!.formatted(date: .omitted, time: .standard))" : "本地分析与候选记录")
                    }
                    Text("工作区授权允许模型在隔离 Linux 中执行脚本，脚本也可能联网。没有独立网络隔离等级；宿主设备、机器人和外部账户控制未开放。")
                    Button("允许工作区工具 30 分钟") { perform { try control.grantWorkspace() } }.accessibilityIdentifier("cognitive.grant")
                    Button("仅允许本地分析与候选记录") { perform { try control.allowAnalysis() } }
                    Button("撤销全部模型工具权限", role: .destructive) { perform { try control.revokeAll() } }.accessibilityIdentifier("cognitive.revoke")
                    Text("撤销会停止正在运行的工具，阻止后续调用并丢弃过期结果；已发生的写入或网络请求不能回滚。模型连接的数据发送许可另行管理。")
                }
                Section("图片观察") {
                    PhotosPicker(selection: $photo, matching: .images) { Label("选择图片并在本机识别文字", systemImage: "photo") }.accessibilityIdentifier("cognitive.photo")
                    if recognizing { ProgressView("识别中…") }
                    if let observation { Text(observation).font(.caption) }
                    Text("只识别图片里的文字，不等同于完整图像理解。图片不发送给模型；识别结果填入可编辑候选表单，核对并启用后才可能随后续对话发送。")
                }
                Section("提交待核对资料") {
                    TextField("主题", text: $topic).accessibilityIdentifier("cognitive.topic")
                    TextField("内容：区分观察、假设与结论", text: $statement, axis: .vertical).accessibilityIdentifier("cognitive.statement")
                    TextField("来源链接、记录编号或实验出处", text: $source).accessibilityIdentifier("cognitive.source")
                    Button("保存候选") { perform { try control.propose(topic: topic, statement: statement, source: source); topic = ""; statement = ""; source = "" } }.accessibilityIdentifier("cognitive.propose")
                    Text("候选不会进入模型上下文。启用前请亲自核对来源和结论。保留检查只验证旧资料未丢失，不证明新结论正确，也不是模型训练。")
                }
                Section("待核对 \(control.candidates.count)") {
                    ForEach(control.candidates) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.topic).font(.headline); Text(item.statement); Text("来源：" + item.source).font(.caption)
                            let existing = control.active.first { $0.topic.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) == item.topic.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
                            if let existing { Text("将替换：" + existing.statement).foregroundStyle(.orange) }
                            Button(existing == nil ? "已核对来源，启用资料" : "已核对，替换上述旧资料") { perform { try control.confirm(item.id, replacing: existing?.id) } }
                            Button("撤回候选") { perform { try control.withdraw(item.id) } }
                        }
                    }
                }
                Section("已核对资料 \(control.active.count)") {
                    ForEach(control.active) { item in
                        VStack(alignment: .leading) {
                            Text(item.topic).font(.headline); Text(item.statement); Text(item.source).font(.caption)
                            Button("撤回此资料") { perform { try control.withdraw(item.id) } }
                        }
                    }
                }
                Section("历史版本") {
                    ForEach(control.state.records.filter { $0.withdrawnAt != nil }.suffix(20)) { item in
                        Button("重新核对：" + item.topic) { perform { try control.restore(item.id) } }
                    }
                }
                Section("现实世界接入状态") {
                    Text("已接入：文本、本机图片文字识别和本地工具输出。\n待接入：通用图像理解、语音转写、机器人和真实实验设备。来源字段可记录实验出处，但不代表验证过实验。")
                }
                Section("审计 \(control.state.audit.count)/2000") {
                    Text("仅记录事件、工具名、调用编号和参数摘要哈希，不保存原始参数。最多2000条，满额停止受管操作，不自动覆盖。")
                    ForEach(control.state.audit.suffix(30).reversed()) { event in
                        VStack(alignment: .leading) { Text(event.event); Text(event.subject).font(.caption); Text(event.date.formatted()).font(.caption2) }
                    }
                }
                if let text = message ?? control.error { Section { Text(text).foregroundStyle(.red) } }
            }.navigationTitle("神枢成长")
                .task(id: photo) {
                    guard let selected = photo else { return }
                    recognizing = true
                    defer { if photo == selected { recognizing = false } }
                    do {
                        guard let data = try await selected.loadTransferable(type: Data.self) else { throw NexusError.invalidResponse }
                        try Task.checkCancellation()
                        let result = try await Task.detached(priority: .userInitiated) { try NexusVisualObservation.recognize(data) }.value
                        try Task.checkCancellation()
                        topic = "图片文字观察"; statement = String(result.text.prefix(1200)); source = result.source
                        observation = "已填入最多1200字；最低识别置信度 \(Int(result.minimumConfidence * 100))%。请对照原图纠错，再保存候选。"
                    } catch is CancellationError {} catch { message = error.localizedDescription }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
