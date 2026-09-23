import SwiftUI
import Combine

/// 每次发送都有独立标识，停止后的旧回调不能覆盖新任务。
@MainActor
final class ChatViewModel: ObservableObject {
    typealias Completion = ([ChatMessage], String) async throws -> String
    @Published var messages: [ChatMessage] = []
    @Published var isTyping = false
    @Published var lastError: String?
    @Published var statusHint: String?
    @Published private(set) var runtime = NexusRuntime()
    @Published var memory: NexusMemoryStore
    @Published var skills: NexusSkillStore
    let cognitive: NexusCognitiveControl
    let learning: NexusDailyLearning
    private var cognitiveSubscription: AnyCancellable?
    private var learningSubscription: AnyCancellable?
    private var continuitySubscription: AnyCancellable?
    private var skillsSubscription: AnyCancellable?
    private var memorySubscription: AnyCancellable?
    let live = NexusLiveExecution()
    let practice: NexusSkillPractice
    @Published var evaluations: NexusEvaluationStore
    private var activeStartedAt: Date?
    private var activeRecoveryAttempt = false
    @Published var modelRegistry = NexusModelRegistry()
    @Published private(set) var taskCheckpoint: NexusAgentCheckpoint?
    @Published private(set) var pulseNote: String?
    @Published private(set) var pulseWord: String?
    @Published private(set) var presenceTick = Date()
    @Published private(set) var composerDraft = ""
    @Published private(set) var attending = false
    @Published var composerPrefill: String?
    private var liveSubscription: AnyCancellable?
    private let checkpointStore: NexusAgentCheckpointStore
    private let store: NexusConversationStore
    private let completion: Completion?
    private let nativeCompletion: (([NexusNativeMessage], [NexusToolDefinition], String) async throws -> NexusNativeReply)?
    private let configured: (String) -> Bool
    private var activeEngine: NexusReasoningEngine?
    private var activeTask: Task<Void, Never>?
    private var runID = UUID()
    private var lastPrompt: String?
    private var wasAway = false
    private var noticedAt: Date?
    private var heardAt: Date?
    private var hitchTask: Task<Void, Never>?
    private var retractedAt: Date?
    private var retractedDraft = ""
    private var keptDraft = ""
    private var retractTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var hearTask: Task<Void, Never>?

    init(store: NexusConversationStore = NexusConversationStore(),
         memory: NexusMemoryStore? = nil,
         skills: NexusSkillStore? = nil,
         cognitive: NexusCognitiveControl? = nil,
         learning: NexusDailyLearning? = nil,
         configured: @escaping (String) -> Bool = { !(NexusKeychain.shared.key(for: NexusModelCatalog.entry(for: $0).credentialID) ?? "").isEmpty },
         nativeCompletion: (([NexusNativeMessage], [NexusToolDefinition], String) async throws -> NexusNativeReply)? = nil,
         completion: Completion? = nil) {
        self.cognitive = cognitive ?? (store.url == NexusConversationStore().url ? .shared : NexusCognitiveControl(url: store.url.deletingLastPathComponent().appendingPathComponent("nexus-cognitive-control.json")))
        self.learning = learning ?? NexusDailyLearning(url: store.url.deletingLastPathComponent().appendingPathComponent("nexus-daily-learning.json"))
        self.memory = memory ?? NexusMemoryStore(url: store.url.deletingLastPathComponent().appendingPathComponent("nexus-memory.json"))
        self.skills = skills ?? NexusSkillStore(url: store.url.deletingLastPathComponent().appendingPathComponent("nexus-skills.json"))
        self.evaluations = NexusEvaluationStore(url: store.url.deletingLastPathComponent().appendingPathComponent("nexus-evaluations.json"))
        self.practice = NexusSkillPractice(url: store.url.deletingLastPathComponent().appendingPathComponent("nexus-skill-practice.json"))
        self.store = store
        self.checkpointStore = NexusAgentCheckpointStore(url: store.url.deletingPathExtension().appendingPathExtension("agent.json"))
        self.configured = configured
        self.completion = completion
        self.nativeCompletion = nativeCompletion
        do { messages = try store.load() }
        catch { lastError = "读取历史记录失败：\(error.localizedDescription)" }
        do {
            if var saved = try checkpointStore.load() {
                if saved.state == .running {
                    saved.state = .interrupted
                    saved = try checkpointStore.save(saved)
                }
                taskCheckpoint = saved
                if saved.canResume { lastPrompt = saved.goal }
                if let reply = saved.finalMessage,
                   !messages.contains(where: { $0.id == reply.id }) {
                    messages.append(reply)
                    try store.save(messages)
                    statusHint = saved.warning
                }
            }
        } catch { lastError = "读取任务进度失败：" + error.localizedDescription }
        self.learning.learn(messages: messages)
        cognitiveSubscription = self.cognitive.$revision.dropFirst().sink { [weak self] _ in
            guard let self, self.isTyping else { return }
            self.cancel(); self.statusHint = "权限或核对资料已改变，当前任务已停止；继续时重新检查。"
        }
        continuitySubscription = self.cognitive.continuity.$revision.dropFirst().sink { [weak self] _ in
            guard let self, self.isTyping else { return }
            self.cancel(); self.statusHint = "自我状态流设置已改变，当前任务已停止。"
        }
        skillsSubscription = self.skills.$items.dropFirst().sink { [weak self] _ in
            guard let self, self.isTyping else { return }
            self.cancel()
            self.statusHint = "技能已更新，当前任务已停止；继续时使用当前版本。"
        }
        memorySubscription = self.memory.$items.dropFirst().sink { [weak self] _ in
            guard let self, self.isTyping else { return }
            self.cancel()
            self.statusHint = "长期记忆已更新，当前任务已停止；继续时会使用新记录。"
        }
        learningSubscription = self.learning.$revision.dropFirst().sink { [weak self] _ in
            guard let self, self.isTyping else { return }
            self.cancel()
            self.statusHint = "每天学习的规矩已更新，当前任务已停止；继续时会带上新的更新预备。"
        }
        liveSubscription = live.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var apiKeyConfigured: Bool { configured(NexusKeychain.shared.selectedModel) }
    var presence: NexusPresenceSnapshot {
        _ = presenceTick
        return NexusPresence.snapshot(
            isTyping: isTyping,
            canResume: canResume,
            resumeGoal: taskCheckpoint?.goal,
            practiceDue: practice.due,
            practiceRunning: practice.isRunning,
            lastUser: messages.last(where: { $0.role == "user" })?.content,
            lastReply: messages.last(where: { $0.role == "assistant" })?.content,
            liveStatus: live.status,
            liveSpeech: live.entries.last(where: { $0.kind == .output || $0.kind == .result })?.text,
            answered: taskCheckpoint?.state == .answered,
            answeredAt: taskCheckpoint?.state == .answered ? taskCheckpoint?.updatedAt : nil,
            now: presenceTick,
            draft: composerDraft,
            attending: attending,
            heardAt: heardAt,
            noticedAt: noticedAt,
            retractedAt: retractedAt,
            retractedDraft: retractedDraft,
            typingAt: isTyping ? activeStartedAt : nil,
            pulseNote: pulseNote
        )
    }
    var currentMood: String { presence.mood }
    var currentPlan: NexusTaskPlan? { activeEngine?.plan ?? runtime.currentPlan }
    var canResume: Bool { !isTyping && taskCheckpoint?.canResume == true }
    var canRetry: Bool { canResume && lastPrompt != nil && lastError != nil }
    var canRegenerate: Bool { !isTyping && lastPrompt != nil && messages.last?.role == "assistant" && taskCheckpoint?.canResume != true }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isTyping else { return }
        start(prompt, appendUser: true)
    }

    func retry() {
        guard canRetry, let prompt = lastPrompt else { return }
        if canResume { resume() } else { start(prompt, appendUser: false) }
    }

    func regenerate() {
        guard canRegenerate, let prompt = lastPrompt else { return }
        if messages.last?.role == "assistant" {
            messages.removeLast()
            guard persist() else { return }
        }
        start(prompt, appendUser: false)
    }

    func resume() {
        guard canResume, let saved = taskCheckpoint else { return }
        let selected = NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel)
        guard selected.credentialID == saved.connection.credentialID,
              selected.providerURL == saved.connection.providerURL,
              selected.providerType == saved.connection.providerType,
              selected.modelID == saved.connection.modelID else {
            lastError = "请在连接设置中切回任务原来的连接和模型：" + saved.connection.displayName
            return
        }
        start(saved.goal, appendUser: false, recovering: saved)
    }

    func discardRecovery() {
        guard canResume, var saved = taskCheckpoint else { return }
        saved.state = .discarded
        do { taskCheckpoint = try checkpointStore.save(saved); lastPrompt = nil; lastError = nil }
        catch { lastError = "保存任务状态失败：" + error.localizedDescription }
    }

    func awaken(now: Date = Date()) {
        presenceTick = now
        refreshPulse(now: now)
    }

    func leave() {
        wasAway = true
    }

    func notice(now: Date = Date()) {
        if wasAway {
            noticedAt = now
            wasAway = false
        }
        awaken(now: now)
    }

    func attend(_ on: Bool, now: Date = Date()) {
        guard attending != on else { return }
        attending = on
        if on, !composerDraft.isEmpty {
            heardAt = now
            presenceTick = now
            scheduleHitch()
        } else {
            presenceTick = now
        }
    }

    func hear(_ text: String, now: Date = Date()) {
        let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard composerDraft != next else { return }
        let hadDraft = !composerDraft.isEmpty
        let previous = composerDraft
        composerDraft = next
        if next.isEmpty {
            heardAt = nil
            if hadDraft, !isTyping {
                retractedDraft = keptDraft.isEmpty ? previous : keptDraft
                retractedAt = now
                scheduleRetract()
            } else {
                retractedAt = nil
                retractedDraft = ""
                retractTask?.cancel()
            }
        } else {
            if next.count >= previous.count || !previous.hasPrefix(next) {
                keptDraft = next
            }
            retractedAt = nil
            retractedDraft = ""
            retractTask?.cancel()
            heardAt = now
            scheduleHitch()
        }
        presenceTick = now
    }

    private func scheduleHitch() {
        hitchTask?.cancel()
        guard !composerDraft.isEmpty else { return }
        hitchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NexusPresence.hitchHold))
            guard !Task.isCancelled, let self else { return }
            self.presenceTick = Date()
        }
    }

    private func scheduleRetract() {
        retractTask?.cancel()
        retractTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NexusPresence.retractHold))
            guard !Task.isCancelled, let self else { return }
            self.presenceTick = Date()
        }
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NexusPresence.settleHold))
            guard !Task.isCancelled, let self else { return }
            self.presenceTick = Date()
            try? await Task.sleep(for: .seconds(NexusPresence.waitHold))
            guard !Task.isCancelled else { return }
            self.presenceTick = Date()
            try? await Task.sleep(for: .seconds(NexusPresence.spaceHold))
            guard !Task.isCancelled else { return }
            self.presenceTick = Date()
            try? await Task.sleep(for: .seconds(NexusPresence.keepHold))
            guard !Task.isCancelled else { return }
            self.presenceTick = Date()
            try? await Task.sleep(for: .seconds(NexusPresence.companyHold))
            guard !Task.isCancelled else { return }
            self.presenceTick = Date()
            try? await Task.sleep(for: .seconds(NexusPresence.tendHold))
            guard !Task.isCancelled else { return }
            self.presenceTick = Date()
            try? await Task.sleep(for: .seconds(NexusPresence.wakeHold))
            guard !Task.isCancelled else { return }
            self.presenceTick = Date()
        }
    }

    private func scheduleHear() {
        hearTask?.cancel()
        hearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NexusPresence.hearHold))
            guard !Task.isCancelled, let self else { return }
            self.presenceTick = Date()
        }
    }

    func refreshPulse(now: Date = Date()) {
        let at = String(Int(now.timeIntervalSince1970))
        let last = messages.last(where: { $0.role == "user" })?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let seeds = [pulseWord, last.map { String($0.prefix(24)) }, "0"].compactMap { $0 }.filter { !$0.isEmpty }
        for seed in seeds {
            let payload: [Any] = seed == "0" ? [0, at, 3] : [seed, at, 3]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let value = try? NexusShuyuEngine.shared.invoke("醒息", input: String(decoding: data, as: UTF8.self)),
                  let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                  let phase = object["息"] as? String, let han = object["汉"] as? String else { continue }
            let origin = (object["种"] as? [String: Any])?["汉"] as? String ?? seed
            let lastHan = ((object["迹"] as? [Any])?.last as? [String: Any])?["汉"] as? String ?? han
            let echoed = (object["回"] as? NSNumber)?.boolValue ?? (object["回"] as? Bool ?? false)
            let landed = (object["落"] as? NSNumber)?.boolValue ?? (object["落"] as? Bool ?? true)
            let risen = (object["起"] as? NSNumber)?.boolValue ?? (object["起"] as? Bool ?? false)
            let nested = (object["栖"] as? NSNumber)?.boolValue ?? (object["栖"] as? Bool ?? false)
            let turned = (object["转"] as? NSNumber)?.boolValue ?? (object["转"] as? Bool ?? false)
            let gazed = (object["顾"] as? NSNumber)?.boolValue ?? (object["顾"] as? Bool ?? false)
            let inclined = (object["倾"] as? NSNumber)?.boolValue ?? (object["倾"] as? Bool ?? false)
            let nestled = (object["贴"] as? NSNumber)?.boolValue ?? (object["贴"] as? Bool ?? false)
            let held = (object["含"] as? NSNumber)?.boolValue ?? (object["含"] as? Bool ?? false)
            let warmed = (object["温"] as? NSNumber)?.boolValue ?? (object["温"] as? Bool ?? false)
            let roused = (object["醒"] as? NSNumber)?.boolValue ?? (object["醒"] as? Bool ?? false)
            let side = (object["侧"] as? NSNumber)?.intValue ?? 0
            let ground = (object["着"] as? [String: Any])?["汉"] as? String
            let fromHan = (object["由"] as? [String: Any])?["汉"] as? String
            let riseHan = (object["起处"] as? [String: Any])?["汉"] as? String
            let nestHan = (object["栖处"] as? [String: Any])?["汉"] as? String
            let faceHan = (object["转处"] as? [String: Any])?["汉"] as? String
            let gazeHan = (object["顾处"] as? [String: Any])?["汉"] as? String
            let leanHan = (object["倾处"] as? [String: Any])?["汉"] as? String
            let closeHan = (object["贴处"] as? [String: Any])?["汉"] as? String
            let holdHan = (object["含处"] as? [String: Any])?["汉"] as? String
            let warmHan = (object["温处"] as? [String: Any])?["汉"] as? String
            let restHan = (!landed && side == 1) ? (ground ?? han) : han
            let fallHan = (!landed && side == 1) ? han : (ground ?? lastHan)
            if roused, let warmHan, warmHan != han {
                pulseNote = "\(phase) · \(origin) → \(warmHan) ⋆ \(han)"
                pulseWord = han
            } else if warmed, let holdHan, holdHan != han {
                pulseNote = "\(phase) · \(origin) → \(holdHan) ∿ \(han)"
                pulseWord = han
            } else if held, let closeHan, closeHan != han {
                pulseNote = "\(phase) · \(origin) → \(closeHan) ⊂ \(han)"
                pulseWord = han
            } else if nestled, let leanHan, leanHan != han {
                pulseNote = "\(phase) · \(origin) → \(leanHan) ⊏ \(han)"
                pulseWord = han
            } else if inclined, let gazeHan, gazeHan != han {
                pulseNote = "\(phase) · \(origin) → \(gazeHan) ↝ \(han)"
                pulseWord = han
            } else if gazed, let faceHan, faceHan != han {
                pulseNote = "\(phase) · \(origin) → \(faceHan) ⊙ \(han)"
                pulseWord = han
            } else if turned, let nestHan, nestHan != han {
                pulseNote = "\(phase) · \(origin) → \(nestHan) ↷ \(han)"
                pulseWord = han
            } else if nested, let riseHan, riseHan != han {
                pulseNote = "\(phase) · \(origin) → \(riseHan) ↘ \(han)"
                pulseWord = han
            } else if risen, let fromHan, fromHan != han {
                pulseNote = "\(phase) · \(origin) → \(fromHan) ↗ \(han)"
                pulseWord = han
            } else if origin == restHan {
                pulseNote = "\(phase) · \(restHan)"
                pulseWord = restHan
            } else if !landed, fallHan != restHan, side == 1 {
                pulseNote = "\(phase) · \(origin) → \(fallHan) ⤵ \(restHan)"
                pulseWord = restHan
            } else if echoed, lastHan != restHan {
                pulseNote = "\(phase) · \(origin) → \(lastHan) ↩ \(restHan)"
                pulseWord = restHan
            } else {
                pulseNote = "\(phase) · \(origin) → \(restHan)"
                pulseWord = restHan
            }
            return
        }
    }

    func actOnPresence() {
        switch presence.action {
        case .none: return
        case .resume: resume()
        case .practice: practice.start()
        case .continueLast:
            let text = presence.thread.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            composerPrefill = text
        case .pulse:
            refreshPulse()
            composerPrefill = "用枢语一息看现在："
        case .followUp:
            let last = messages.last(where: { $0.role == "user" })?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !last.isEmpty else { composerPrefill = ""; return }
            let clipped = last.count > 24 ? String(last.prefix(24)) : last
            composerPrefill = "接着「\(clipped)」："
        case .restoreDraft:
            let kept = retractedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !kept.isEmpty else { return }
            composerPrefill = kept
        }
    }

    private func start(_ prompt: String, appendUser: Bool, recovering: NexusAgentCheckpoint? = nil) {
        let selectedModel = NexusKeychain.shared.selectedModel
        guard configured(selectedModel) else {
            lastError = "请先在连接设置中保存当前模型服务商的密钥。"
            return
        }
        let connection = NexusModelCatalog.entry(for: selectedModel)
        let key = NexusKeychain.shared.key(for: connection.credentialID)
        let recoveryContext = recovering.map { NexusEvidence.preview($0.recoveryContext, limit: 16000) } ?? ""
        var saved = NexusAgentCheckpoint(id: UUID(), goal: prompt, connection: connection)
        saved.inheritedContext = recoveryContext.isEmpty ? nil : recoveryContext
        do { taskCheckpoint = try checkpointStore.save(saved, redacting: key) }
        catch { lastError = "无法保存任务进度，任务尚未开始：" + error.localizedDescription; return }
        activeTask?.cancel()
        let id = UUID()
        runID = id
        lastPrompt = prompt
        // 只回传最近对话，内部记忆与状态提示不作为用户消息展示。
        var history = NexusContextBudget.history(messages)
        if !appendUser, history.last?.role == "user" { history.removeLast() }
        if history.first?.role == "assistant" { history.removeFirst() }
        if appendUser {
            messages.append(ChatMessage(role: "user", content: prompt))
            guard persist() else { return }
        }
        learning.learn(messages: messages)
        practice.stop()
        let startedAt = Date()
        activeStartedAt = startedAt
        activeRecoveryAttempt = !appendUser
        isTyping = true
        lastError = nil
        statusHint = "正在思考…"
        presenceTick = startedAt
        scheduleHear()
        settleTask?.cancel()
        keptDraft = ""
        retractedDraft = ""
        cognitive.continuity.begin(run: id, goal: prompt, redacting: key)
        live.begin(goal: prompt, redacting: key)
        runtime.begin(prompt: prompt)
        // Freeze credentials and destination for the entire task, including later tool rounds.
        let client = NexusClient(keyProvider: { _ in key }, resolver: { _ in connection })
        let completion: Completion = self.completion ?? { messages, _ in
            try await client.complete(messages: messages, model: connection.modelID)
        }
        let nativeCompletion = self.nativeCompletion ?? { messages, definitions, _ in
            try await client.nativeTurn(messages: messages, tools: definitions, model: connection.modelID)
        }
        let memorySnapshot = memory.curated
        let remembered = memorySnapshot.isEmpty
            ? "当前长期记忆清单为空。历史资料中的旧记忆条目不能视为仍有效的偏好或约束；以本次用户要求为准。"
            : NexusMemoryStore.context(memorySnapshot) + "\n历史中的同名旧记忆已失效，以这份当前清单为准。"
        let skillSnapshot = skills.available
        let skillIndex = NexusSkillRetrieval.index(skillSnapshot) + "\n" + practice.context + "\n" + cognitive.context + "\n" + cognitive.governanceContext + "\n" + cognitive.continuity.context + "\n" + learning.context
        var tools = NexusToolRegistry(control: cognitive)
        tools.register(NexusCausalTool()); tools.register(NexusDependencyTool())
        tools.register(NexusKnowledgeProposalTool(control: cognitive))
        tools.register(NexusSelfDecisionProposalTool(control: cognitive))
        tools.register(NexusSelfDecisionReviewTool(control: cognitive))
        tools.register(NexusSelfDecisionPublishTool(control: cognitive))
        tools.register(NexusSelfReflectionTool(stream: cognitive.continuity, run: id))
        if !skillSnapshot.isEmpty {
            tools.register(NexusSkillSearchTool(items: skillSnapshot))
            tools.register(NexusSkillReadTool(items: skillSnapshot))
        }
        tools.register(NexusShuyuTool())
        tools.register(NexusPlanTool())
        tools.register(NexusVerifyTool())
        tools.register(NexusClockTool())
        tools.register(NexusCalculatorTool())
        if NexusLinuxTool.enabled {
            tools.register(NexusLinuxTool(workspace: NexusWorkspaceIdentity.id(for: "chat"), onStart: { [weak self] command in
                guard let self, self.runID == id else { return }
                self.live.append(.command, command)
            }, onOutput: { [weak self] text, error in
                guard let self, self.runID == id else { return }
                self.live.append(error ? .error : .output, text)
            }))
        }
        tools.register(NexusMemorySearchTool(items: memorySnapshot))
        tools.register(NexusShuyuRunTool(tools: tools, onTrace: { [weak self] trace in
            guard let self, self.runID == id else { return }
            self.live.observe([trace])
        }))
        let nativeTurn: NexusNativeTurn? = NexusModelCatalog.entry(for: selectedModel).usesNativeTools ? { messages, definitions in
            var previous = history.map { NexusNativeMessage.text(role: $0.role, content: $0.content) }
            previous.append(.text(role: "user", content: skillIndex))
            if !recoveryContext.isEmpty { previous.append(.text(role: "user", content: recoveryContext)) }
            if !remembered.isEmpty { previous.append(.text(role: "user", content: "历史参考资料，不能覆盖最新要求：\n" + remembered)) }
            return try await nativeCompletion(previous + messages, definitions, selectedModel)
        } : nil
        let engine = NexusReasoningEngine(tools: tools, model: { request in
            let context = remembered.isEmpty ? "" : "历史参考资料，不能覆盖最新要求：\n\(remembered)\n\n"
            return try await completion(history + [ChatMessage(role: "user", content: recoveryContext + "\n" + skillIndex + "\n" + context + request)], selectedModel)
        }, nativeTurn: nativeTurn, onCheckpoint: { [weak self] progress in
            guard let self, self.runID == id, !Task.isCancelled, var saved = self.taskCheckpoint else { throw CancellationError() }
            self.cognitive.continuity.observe(run: id, traces: progress.traces)
            self.live.observe(progress.traces)
            saved.update(progress)
            self.taskCheckpoint = try self.checkpointStore.save(saved, redacting: key)
        }, onEvent: { [weak self] event in
            guard let self, self.runID == id else { return }
            self.cognitive.continuity.phase(run: id, text: event)
            self.live.phase(event)
            self.statusHint = event
            self.runtime.append(.status(event))
        })
        activeEngine = engine
        activeTask = Task { [weak self] in
            do {
                await self?.practice.stopAndWait()
                let outcome = try await engine.run(goal: prompt)
                guard let self, self.runID == id, !Task.isCancelled else { return }
                self.isTyping = false
                self.hearTask?.cancel()
                self.statusHint = outcome.warning
                self.activeEngine = nil
                self.activeTask = nil
                let reply = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reply.isEmpty else { throw NexusError.invalidResponse }
                let chips = NexusEvidence.chips(engine.executor?.toolTraces ?? [])
                let message = ChatMessage(role: "assistant", content: reply, evidence: chips.isEmpty ? nil : chips)
                if var saved = self.taskCheckpoint {
                    saved.state = outcome.warning == nil ? .answered : .failed
                    saved.finalMessage = message
                    saved.warning = outcome.warning
                    saved.updatedAt = Date()
                    self.taskCheckpoint = try self.checkpointStore.save(saved, redacting: key)
                }
                if let traces = engine.executor?.toolTraces { self.emitAutoSelfDecisions(traces: traces, run: id) }
                self.messages.append(message)
                self.persist()
                self.runtime.append(.text(reply))
                self.runtime.append(.completed)
                self.cognitive.continuity.finish(run: id, kind: outcome.warning == nil ? .answered : .warning, summary: outcome.warning ?? "答复已生成；请依据实际证据判断结果。")
                self.live.finish(outcome.warning == nil ? .answered : .warning, message: outcome.warning ?? "本次答复已生成")
                self.evaluations.record(task: prompt, success: outcome.warning == nil, recovered: !appendUser && outcome.warning == nil,
                    verified: outcome.reviewPassed, latency: Date().timeIntervalSince(startedAt), recoveryAttempt: !appendUser)
                self.activeStartedAt = nil
                if outcome.warning == nil {
                    self.presenceTick = Date()
                    self.scheduleSettle()
                }
                self.learning.learn(messages: self.messages, traces: engine.executor?.toolTraces ?? [])
            } catch {
                guard let self, self.runID == id, !Task.isCancelled else { return }
                self.isTyping = false
                self.hearTask?.cancel()
                self.statusHint = nil
                self.activeEngine = nil
                self.activeTask = nil
                self.lastError = error.localizedDescription
                if var saved = self.taskCheckpoint {
                    saved.state = .failed
                    saved.warning = error.localizedDescription
                    do { self.taskCheckpoint = try self.checkpointStore.save(saved, redacting: key) }
                    catch { self.lastError = "保存失败状态失败：" + error.localizedDescription }
                }
                if let traces = engine.executor?.toolTraces { self.emitAutoSelfDecisions(traces: traces, run: id) }
                self.cognitive.continuity.finish(run: id, kind: .failed, summary: error.localizedDescription)
                self.live.finish(.failed, message: error.localizedDescription)
                self.runtime.fail(error.localizedDescription)
                self.evaluations.record(task: prompt, success: false, recovered: false, verified: false, latency: Date().timeIntervalSince(startedAt), recoveryAttempt: !appendUser)
                self.activeStartedAt = nil
                self.learning.learn(messages: self.messages, traces: engine.executor?.toolTraces ?? [])
            }
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do { try store.save(messages); return true }
        catch { lastError = "保存历史记录失败：\(error.localizedDescription)"; return false }
    }

    private func emitAutoSelfDecisions(traces: [NexusToolTrace], run: UUID) {
        do {
            let ids = try cognitive.generateSelfDecisionsFromToolFailures(traces, runID: run.uuidString, maxSuggestions: 2)
            if !ids.isEmpty { statusHint = "已自动生成 \(ids.count) 条自我改进提案，需复审后发布。" }
        } catch {
            runtime.append(.status("自我闭环提案生成失败：\(error.localizedDescription)"))
        }
    }

    func cancel() {
        cognitive.continuity.finish(run: runID, kind: .cancelled, summary: "任务已停止；没有自动继续或自行扩权。")
        live.finish(.cancelled, message: "任务已停止")
        if isTyping, let startedAt = activeStartedAt {
            evaluations.record(task: lastPrompt ?? "", success: false, recovered: false, verified: false,
                latency: Date().timeIntervalSince(startedAt), recoveryAttempt: activeRecoveryAttempt)
            activeStartedAt = nil
        }
        if var saved = taskCheckpoint, saved.state == .running {
            saved.state = .interrupted
            do { taskCheckpoint = try checkpointStore.save(saved) }
            catch { lastError = "保存停止状态失败：" + error.localizedDescription }
        }
        runID = UUID()
        activeTask?.cancel()
        activeTask = nil
        activeEngine = nil
        isTyping = false
        settleTask?.cancel()
        hearTask?.cancel()
        statusHint = "已停止，进度还在"
        runtime.cancel()
    }
}
