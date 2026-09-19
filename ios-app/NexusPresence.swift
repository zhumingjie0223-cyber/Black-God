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

/// 打开就要在场：空着会看，写着会顿，草稿还惦记，收回去会收笔还能还给你，开口会说，说完会落定再等下文，等久了会让开，盯着空框会侧耳，回来还在，刚接话会应声，落定后还衔着刚才，接着写会跟上，说话时在听，刚歇会褪，停了还在，不自动扩权。
enum NexusPresence {
    static let afterglow: TimeInterval = 180
    static let echoFade: TimeInterval = 900
    static let noticeHold: TimeInterval = 12
    static let hitchHold: TimeInterval = 1.6
    static let retractHold: TimeInterval = 4
    static let settleHold: TimeInterval = 6
    static let waitHold: TimeInterval = 8
    static let spaceHold: TimeInterval = 8
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
                return NexusPresenceSnapshot(
                    mood: "开口", stance: "speaking", thread: clip(resumeGoal ?? lastUser),
                    nextWork: spoken, actionTitle: "", action: .none, breath: 0.7
                )
            }
            let step = clip(liveStatus)
            let heardAgo = typingAt.map { now.timeIntervalSince($0) }
            if heardAgo.map({ $0 < hearHold }) == true || step.isEmpty || step == "正在理解任务" {
                return NexusPresenceSnapshot(
                    mood: "应声", stance: "answering", thread: clip(resumeGoal ?? lastUser),
                    nextWork: "听见了", actionTitle: "", action: .none, breath: 0.6
                )
            }
            return NexusPresenceSnapshot(
                mood: "处理中", stance: "working", thread: clip(resumeGoal ?? lastUser),
                nextWork: step, actionTitle: "", action: .none, breath: 0.9
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
            if attending {
                if let heard = heardAt, now.timeIntervalSince(heard) >= hitchHold {
                    return NexusPresenceSnapshot(
                        mood: "顿笔", stance: "hitching", thread: spoken,
                        nextWork: "等你写完", actionTitle: "", action: .none, breath: 1.5
                    )
                }
                if answered {
                    let age = answeredAt.map { now.timeIntervalSince($0) }
                    if age == nil || age! < echoFade {
                        return NexusPresenceSnapshot(
                            mood: "跟上", stance: "following", thread: spoken,
                            nextWork: "你接着说", actionTitle: "", action: .none, breath: 1.05
                        )
                    }
                }
                return NexusPresenceSnapshot(
                    mood: "在听", stance: "listening", thread: spoken,
                    nextWork: "你正在说", actionTitle: "", action: .none, breath: 1.1
                )
            }
            return NexusPresenceSnapshot(
                mood: "惦记", stance: "holding", thread: spoken,
                nextWork: "你写到这儿了", actionTitle: "", action: .none, breath: 2.0
            )
        }
        if let retracted = retractedAt {
            let ago = now.timeIntervalSince(retracted)
            if ago >= 0, ago < retractHold {
                let kept = clip(retractedDraft)
                return NexusPresenceSnapshot(
                    mood: "收笔", stance: "retracting", thread: kept.isEmpty ? clip(pulseNote ?? lastReply ?? lastUser) : kept,
                    nextWork: "你收回去了",
                    actionTitle: kept.isEmpty ? "" : "还给你",
                    action: kept.isEmpty ? .none : .restoreDraft, breath: 1.3
                )
            }
        }
        if answered {
            let age = answeredAt.map { now.timeIntervalSince($0) }
            if age == nil || age! < settleHold {
                let spoken = clip(lastReply)
                return NexusPresenceSnapshot(
                    mood: "落定", stance: "exhaling", thread: spoken.isEmpty ? clip(resumeGoal ?? lastUser) : spoken,
                    nextWork: "刚说到这儿",
                    actionTitle: "接着问", action: .followUp, breath: 1.0
                )
            }
        }
        if attending {
            if answered {
                let age = answeredAt.map { now.timeIntervalSince($0) }
                if age == nil || age! < echoFade {
                    let spoken = clip(lastReply)
                    if let age, age >= settleHold + waitHold {
                        return NexusPresenceSnapshot(
                            mood: "侧耳", stance: "heeding", thread: spoken.isEmpty ? clip(resumeGoal ?? lastUser) : spoken,
                            nextWork: "侧耳听着",
                            actionTitle: "接着问", action: .followUp, breath: 1.25
                        )
                    }
                    return NexusPresenceSnapshot(
                        mood: "衔着", stance: "carrying", thread: spoken.isEmpty ? clip(resumeGoal ?? lastUser) : spoken,
                        nextWork: "还接着刚才",
                        actionTitle: "接着问", action: .followUp, breath: 1.2
                    )
                }
            }
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
            if age != nil, age! >= settleHold, age! < settleHold + waitHold {
                let spoken = clip(lastReply)
                return NexusPresenceSnapshot(
                    mood: "等下文", stance: "awaiting", thread: spoken.isEmpty ? clip(resumeGoal ?? lastUser) : spoken,
                    nextWork: "还等你接下句",
                    actionTitle: "接着问", action: .followUp, breath: 1.6
                )
            }
            if age != nil, age! >= settleHold + waitHold, age! < settleHold + waitHold + spaceHold {
                let spoken = clip(lastReply)
                return NexusPresenceSnapshot(
                    mood: "让开", stance: "yielding", thread: spoken.isEmpty ? clip(resumeGoal ?? lastUser) : spoken,
                    nextWork: "先让你想",
                    actionTitle: "接着问", action: .followUp, breath: 1.7
                )
            }
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
