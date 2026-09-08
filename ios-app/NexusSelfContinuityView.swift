import SwiftUI

struct NexusSelfContinuityView: View {
    @ObservedObject var stream: NexusSelfContinuity
    @State private var message: String?
    @State private var clearing = false
    private func perform(_ action: () throws -> Void) { do { try action(); message = nil } catch { message = error.localizedDescription } }
    var body: some View {
        Form {
            Section("神枢的自我状态") {
                Text("我是 Black God，围绕用户授权的目标工作，保留判断、疑问与修正记录。这里展示任务状态与公开摘要，不代表主观体验或内部思维链。")
                Text("连续记录编号：" + stream.state.identity.uuidString.prefix(8)).font(.caption)
                Text(stream.available ? (stream.state.activeRun == nil ? "等待任务" : "任务进行中") : "记录已暂停或不可用").accessibilityIdentifier("self.status")
                if !stream.state.goal.isEmpty { Text("最近目标：" + stream.state.goal) }
                Toggle("自动记录任务状态", isOn: Binding(get: { stream.state.enabled }, set: { enabled in perform { try stream.setEnabled(enabled) } })).accessibilityIdentifier("self.enabled")
                Text("任务事件触发记录，不额外请求模型。休眠时不持续思考，不自动续跑旧计划；暂停或清空会停止当前聊天，避免继续使用旧摘要。")
            }
            Section("连续状态流") {
                Text("保留最近120条，较早记录已移除 \(stream.state.omitted) 条。模型自评不等于事实，待办建议不等于授权。")
                if stream.state.entries.isEmpty { Text("下一次聊天任务开始后，这里将自动出现记录。").accessibilityIdentifier("self.empty") }
                ForEach(stream.state.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label(entry.kind)).font(.headline)
                        Text(entry.summary)
                        Text("未确定：" + entry.uncertainty).font(.caption)
                        Text("下一步：" + entry.nextStep).font(.caption)
                        Text(entry.date.formatted()).font(.caption2)
                    }
                }
            }
            Section("记录管理") {
                Text("摘要保存在本机；最近6条可能随后续获准的模型请求发送。不要记录密码或密钥。清空只删除此状态流，不删除聊天、知识、任务检查点或服务商已有记录。")
                Button("清空自我状态流", role: .destructive) { clearing = true }.accessibilityIdentifier("self.clear")
            }
            if let text = message ?? stream.error { Section { Text(text).foregroundStyle(.red) } }
        }.navigationTitle("自我状态流")
            .confirmationDialog("清空状态流并重新开始连续记录？", isPresented: $clearing, titleVisibility: .visible) {
                Button("清空记录", role: .destructive) { perform { try stream.clear() } }
            }
    }
    private func label(_ kind: NexusSelfContinuity.Kind) -> String {
        switch kind {
        case .started: return "目标已接收"
        case .phase: return "执行阶段"
        case .toolResult: return "工具返回状态"
        case .reflection: return "模型公开自评 · 未验证"
        case .answered: return "答复已生成"
        case .warning: return "仍有待核对项"
        case .failed: return "执行失败"
        case .cancelled: return "用户或权限变更停止"
        case .interrupted: return "记录中断"
        }
    }
}
