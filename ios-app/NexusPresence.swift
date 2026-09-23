import Foundation

enum NexusPresenceAction: String, Equatable {
    case none, resume, practice, continueLast, pulse, followUp, restoreDraft
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

/// 打开就要感到活：在场、呼吸、接得上。
/// 心情只留五种人能读懂的：在场 / 在听 / 在做 / 接得上 / 该练。
/// 不绑人物，不自动扩权。
enum NexusPresence {
    static let moods = ["在场", "在听", "在做", "接得上", "该练"]
    static let afterglow: TimeInterval = 180
    static let echoFade: TimeInterval = 900
    static let noticeHold: TimeInterval = 12
    static let hitchHold: TimeInterval = 1.6
    static let retractHold: TimeInterval = 4
    static let settleHold: TimeInterval = 6
    static let hearHold: TimeInterval = 0.8

    static func snapshot(
        isTyping: Bool,
        canResume: Bool,
        resumeGoal: String?,
        practiceDue: Bool,
        practiceRunning: Bool,
        lastUser: String?,
        lastReply: String? = nil,
        liveStatus: String? = nil,
        liveSpeech: String? = nil,
        answered: Bool = false,
        answeredAt: Date? = nil,
        now: Date = Date(),
        draft: String? = nil,
        attending: Bool = false,
        heardAt: Date? = nil,
        noticedAt: Date? = nil,
        retractedAt: Date? = nil,
        retractedDraft: String? = nil,
        typingAt: Date? = nil,
        pulseNote: String?
    ) -> NexusPresenceSnapshot {
        if isTyping {
            let spoken = clip(liveSpeech)
            if !spoken.isEmpty {
                return make(
                    mood: "在做", stance: "speaking", thread: clip(resumeGoal ?? lastUser),
                    nextWork: spoken, breath: 0.7
                )
            }
            let step = clip(liveStatus)
            let heardAgo = typingAt.map { now.timeIntervalSince($0) }
            if heardAgo.map({ $0 < hearHold }) == true || step.isEmpty || step == "正在理解任务" {
                return make(
                    mood: "在做", stance: "answering", thread: clip(resumeGoal ?? lastUser),
                    nextWork: "听见了", breath: 0.6
                )
            }
            return make(
                mood: "在做", stance: "working", thread: clip(resumeGoal ?? lastUser),
                nextWork: step, breath: 0.9
            )
        }
        if canResume {
            return make(
                mood: "接得上", stance: "recoverable", thread: clip(resumeGoal),
                nextWork: "刚停，进度还在", actionTitle: "继续未完成", action: .resume, breath: 1.6
            )
        }
        let spoken = clip(draft)
        if !spoken.isEmpty {
            if attending {
                if let heard = heardAt, now.timeIntervalSince(heard) >= hitchHold {
                    return make(
                        mood: "在听", stance: "hitching", thread: spoken,
                        nextWork: "等你写完", breath: 1.5
                    )
                }
                if answered {
                    let age = answeredAt.map { now.timeIntervalSince($0) }
                    if age == nil || age! < echoFade {
                        return make(
                            mood: "在听", stance: "following", thread: spoken,
                            nextWork: "你接着说", breath: 1.05
                        )
                    }
                }
                return make(
                    mood: "在听", stance: "listening", thread: spoken,
                    nextWork: "你正在说", breath: 1.1
                )
            }
            return make(
                mood: "在听", stance: "holding", thread: spoken,
                nextWork: "你写到这儿了", breath: 2.0
            )
        }
        if let retracted = retractedAt {
            let ago = now.timeIntervalSince(retracted)
            if ago >= 0, ago < retractHold {
                let kept = clip(retractedDraft)
                return make(
                    mood: "在听", stance: "retracting",
                    thread: kept.isEmpty ? clip(pulseNote ?? lastReply ?? lastUser) : kept,
                    nextWork: "你收回去了",
                    actionTitle: kept.isEmpty ? "" : "还给你",
                    action: kept.isEmpty ? .none : .restoreDraft, breath: 1.3
                )
            }
        }
        if answered {
            let age = answeredAt.map { now.timeIntervalSince($0) }
            if age == nil || age! < settleHold {
                let reply = clip(lastReply)
                return make(
                    mood: "接得上", stance: "exhaling",
                    thread: reply.isEmpty ? clip(resumeGoal ?? lastUser) : reply,
                    nextWork: "刚说到这儿", actionTitle: "接着问", action: .followUp, breath: 1.0
                )
            }
        }
        if attending {
            if answered {
                let age = answeredAt.map { now.timeIntervalSince($0) }
                if age == nil || age! < echoFade {
                    let reply = clip(lastReply)
                    return make(
                        mood: "接得上", stance: "carrying",
                        thread: reply.isEmpty ? clip(resumeGoal ?? lastUser) : reply,
                        nextWork: "还接着刚才", actionTitle: "接着问", action: .followUp, breath: 1.4
                    )
                }
            }
            return make(
                mood: "在场", stance: "watching", thread: clip(pulseNote ?? lastReply ?? lastUser),
                nextWork: pulseNote.map { "等你开口 · \($0)" } ?? "等你开口", breath: 1.4
            )
        }
        if let seen = noticedAt {
            let ago = now.timeIntervalSince(seen)
            if ago >= 0, ago < noticeHold {
                let last = clip(lastUser)
                let hasThread = answered || !last.isEmpty
                let action: NexusPresenceAction = answered ? .followUp : (last.isEmpty ? .pulse : .continueLast)
                let title = action == .followUp ? "接着问" : (action == .pulse ? "看此刻" : "接着上次")
                return make(
                    mood: hasThread ? "接得上" : "在场",
                    stance: "noticing",
                    thread: clip(lastReply ?? lastUser ?? pulseNote),
                    nextWork: pulseNote.map { "你回来了 · \($0)" } ?? "你回来了，还在",
                    actionTitle: title, action: action, breath: 1.8
                )
            }
        }
        if answered {
            let age = answeredAt.map { now.timeIntervalSince($0) } ?? 0
            let reply = clip(lastReply)
            let thread = reply.isEmpty ? clip(resumeGoal ?? lastUser) : reply
            if age < afterglow {
                return make(
                    mood: "接得上", stance: "carrying", thread: thread,
                    nextWork: pulseNote.map { "还在 · \($0)" } ?? "还等你接下句",
                    actionTitle: "接着问", action: .followUp, breath: 1.8
                )
            }
            if age < echoFade {
                return make(
                    mood: "接得上", stance: "echoing", thread: clip(lastReply ?? lastUser),
                    nextWork: pulseNote.map { "刚才说过 · \($0)" } ?? "刚才说过，还在",
                    actionTitle: "接着问", action: .followUp, breath: 2.2
                )
            }
        }
        if practiceRunning || practiceDue {
            return make(
                mood: "该练", stance: "practice", thread: clip(pulseNote),
                nextWork: practiceRunning ? "演练进行中" : "到点该练技能",
                actionTitle: practiceRunning ? "" : "开始演练",
                action: practiceRunning ? .none : .practice, breath: 1.2
            )
        }
        let last = clip(lastUser)
        if !last.isEmpty {
            return make(
                mood: "接得上", stance: "present", thread: last,
                nextWork: pulseNote.map { "接着上次 · \($0)" } ?? "接着上次",
                actionTitle: "接着上次", action: .continueLast, breath: 2.0
            )
        }
        return make(
            mood: "在场", stance: "present", thread: clip(pulseNote),
            nextWork: pulseNote.map { "此刻 \($0)" } ?? "自己找事：一息",
            actionTitle: "看此刻", action: .pulse, breath: 2.4
        )
    }

    private static func make(
        mood: String,
        stance: String,
        thread: String,
        nextWork: String,
        actionTitle: String = "",
        action: NexusPresenceAction = .none,
        breath: Double
    ) -> NexusPresenceSnapshot {
        NexusPresenceSnapshot(
            mood: mood, stance: stance, thread: thread, nextWork: nextWork,
            actionTitle: actionTitle, action: action, breath: breath
        )
    }

    private static func clip(_ text: String?, limit: Int = 48) -> String {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return "" }
        return value.count > limit ? String(value.prefix(limit)) : value
    }
}
