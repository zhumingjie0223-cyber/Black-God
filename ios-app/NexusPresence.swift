import Foundation

enum NexusPresenceAction: String, Equatable {
    case none, resume, practice, continueLast, pulse
}

struct NexusPresenceSnapshot: Equatable {
    var mood: String
    var stance: String
    var thread: String
    var nextWork: String
    var actionTitle: String
    var action: NexusPresenceAction
    var breath: Double
}

/// 打开就要在场：按任务、演练、上次话头和一息决定下一步，不自动扩权。
enum NexusPresence {
    static func snapshot(
        isTyping: Bool,
        canResume: Bool,
        resumeGoal: String?,
        practiceDue: Bool,
        practiceRunning: Bool,
        lastUser: String?,
        pulseNote: String?
    ) -> NexusPresenceSnapshot {
        if isTyping {
            return NexusPresenceSnapshot(
                mood: "处理中", stance: "working", thread: clip(resumeGoal ?? lastUser),
                nextWork: "正在做事", actionTitle: "", action: .none, breath: 0.9
            )
        }
        if canResume {
            let goal = clip(resumeGoal)
            return NexusPresenceSnapshot(
                mood: "可续", stance: "recoverable", thread: goal,
                nextWork: "未完成任务还在", actionTitle: "继续未完成", action: .resume, breath: 1.6
            )
        }
        if practiceRunning || practiceDue {
            return NexusPresenceSnapshot(
                mood: "该练", stance: "practice", thread: clip(pulseNote),
                nextWork: practiceRunning ? "演练进行中" : "到点该练技能",
                actionTitle: practiceRunning ? "" : "开始演练",
                action: practiceRunning ? .none : .practice, breath: 1.2
            )
        }
        if let last = clip(lastUser), !last.isEmpty {
            return NexusPresenceSnapshot(
                mood: "在场", stance: "present", thread: last,
                nextWork: pulseNote.map { "接着上次 · \($0)" } ?? "接着上次",
                actionTitle: "接着上次", action: .continueLast, breath: 2.4
            )
        }
        return NexusPresenceSnapshot(
            mood: "在场", stance: "present", thread: clip(pulseNote),
            nextWork: pulseNote.map { "此刻 \($0)" } ?? "自己找事：一息",
            actionTitle: "看此刻", action: .pulse, breath: 2.4
        )
    }

    private static func clip(_ text: String?) -> String {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return "" }
        return value.count > 48 ? String(value.prefix(48)) : value
    }
}
