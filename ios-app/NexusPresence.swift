import Foundation

enum NexusPresenceAction: String, Equatable {
    case none, resume, practice, continueLast, pulse, followUp
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

/// 打开就要在场：空着会看，回来还在，说话时在听，刚歇会褪，停了还在，不自动扩权。
enum NexusPresence {
    static let afterglow: TimeInterval = 180
    static let echoFade: TimeInterval = 900
    static let noticeHold: TimeInterval = 12

    static func snapshot(
        isTyping: Bool,
        canResume: Bool,
        resumeGoal: String?,
        practiceDue: Bool,
        practiceRunning: Bool,
        lastUser: String?,
        lastReply: String? = nil,
        liveStatus: String? = nil,
        answered: Bool = false,
        answeredAt: Date? = nil,
        now: Date = Date(),
        draft: String? = nil,
        attending: Bool = false,
        noticedAt: Date? = nil,
        pulseNote: String?
    ) -> NexusPresenceSnapshot {
        if isTyping {
            let step = clip(liveStatus)
            return NexusPresenceSnapshot(
                mood: "处理中", stance: "working", thread: clip(resumeGoal ?? lastUser),
                nextWork: step.isEmpty ? "正在做事" : step, actionTitle: "", action: .none, breath: 0.9
            )
        }
        if canResume {
            let goal = clip(resumeGoal)
            return NexusPresenceSnapshot(
                mood: "可续", stance: "recoverable", thread: goal,
                nextWork: "刚停，进度还在", actionTitle: "继续未完成", action: .resume, breath: 1.6
            )
        }
        let spoken = clip(draft)
        if !spoken.isEmpty {
            return NexusPresenceSnapshot(
                mood: "在听", stance: "listening", thread: spoken,
                nextWork: "你正在说", actionTitle: "", action: .none, breath: 1.1
            )
        }
        if attending {
            return NexusPresenceSnapshot(
                mood: "看着", stance: "watching", thread: clip(pulseNote ?? lastReply ?? lastUser),
                nextWork: pulseNote.map { "等你开口 · \($0)" } ?? "等你开口",
                actionTitle: "", action: .none, breath: 1.4
            )
        }
        if let seen = noticedAt {
            let ago = now.timeIntervalSince(seen)
            if ago >= 0, ago < noticeHold {
                let last = clip(lastUser)
                let action: NexusPresenceAction = answered ? .followUp : (last.isEmpty ? .pulse : .continueLast)
                let title = action == .followUp ? "接着问" : (action == .pulse ? "看此刻" : "接着上次")
                return NexusPresenceSnapshot(
                    mood: "还在", stance: "noticing", thread: clip(lastReply ?? lastUser ?? pulseNote),
                    nextWork: pulseNote.map { "你回来了 · \($0)" } ?? "你回来了，还在",
                    actionTitle: title, action: action, breath: 1.8
                )
            }
        }
        if answered {
            let age = answeredAt.map { now.timeIntervalSince($0) }
            if age == nil || age! < afterglow {
                return NexusPresenceSnapshot(
                    mood: "刚歇", stance: "settled", thread: clip(lastReply ?? resumeGoal ?? lastUser),
                    nextWork: pulseNote.map { "还在 · \($0)" } ?? "还在，可接着问",
                    actionTitle: "接着问", action: .followUp, breath: 3.2
                )
            }
            if age! < echoFade {
                return NexusPresenceSnapshot(
                    mood: "余韵", stance: "echoing", thread: clip(lastReply ?? lastUser),
                    nextWork: pulseNote.map { "余音 · \($0)" } ?? "刚才说过，还在",
                    actionTitle: "接着问", action: .followUp, breath: 2.2
                )
            }
        }
        if practiceRunning || practiceDue {
            return NexusPresenceSnapshot(
                mood: "该练", stance: "practice", thread: clip(pulseNote),
                nextWork: practiceRunning ? "演练进行中" : "到点该练技能",
                actionTitle: practiceRunning ? "" : "开始演练",
                action: practiceRunning ? .none : .practice, breath: 1.2
            )
        }
        let last = clip(lastUser)
        if !last.isEmpty {
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

    private static func clip(_ text: String?, limit: Int = 48) -> String {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return "" }
        return value.count > limit ? String(value.prefix(limit)) : value
    }
}
