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
    private var cognitiveSubscription: AnyCancellable?
    private var skillsSubscription: AnyCancellable?
    private var memorySubscription: AnyCancellable?
    let live = NexusLiveExecution()
    let practice: NexusSkillPractice
    @Published var evaluations: NexusEvaluationStore
    private var activeStartedAt: Date?
    private var activeRecoveryAttempt = false
    @Published var modelRegistry = NexusModelRegistry()
    @Published private(set) var taskCheckpoint: NexusAgentCheckpoint?
    private let checkpointStore: NexusAgentCheckpointStore
    private let store: NexusConversationStore
    private let completion: Completion?
    private let nativeCompletion: (([NexusNativeMessage], [NexusToolDefinition], String) async throws -> NexusNativeReply)?
    private let configured: (String) -> Bool
    private var activeEngine: NexusReasoningEngine?
    private var activeTask: Task<Void, Never>?
    private var runID = UUID()
    private var lastPrompt: String?

    init(store: NexusConversationStore = NexusConversationStore(),
         memory: NexusMemoryStore? = nil,
         skills: NexusSkillStore? = nil,
         cognitive: NexusCognitiveControl? = nil,
         configured: @escaping (String) -> Bool = { !(NexusKeychain.shared.key(for: NexusModelCatalog.entry(for: $0).credentialID) ?? "").isEmpty },
         nativeCompletion: (([NexusNativeMessage], [NexusToolDefinition], String) async throws -> NexusNativeReply)? = nil,
         completion: Completion? = nil) {
        self.cognitive = cognitive ?? (store.url == NexusConversationStore().url ? .shared : NexusCognitiveControl(url: store.url.deletingLastPathComponent().appendingPathComponent("nexus-cognitive-control.json")))
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
        cognitiveSubscription = self.cognitive.$revision.dropFirst().sink { [weak self] _ in
            guard let self, self.isTyping else { return }
            self.cancel(); self.statusHint = "权限或核对资料已改变，当前任务已停止；继续时重新检查。"
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
    }

    var apiKeyConfigured: Bool { configured(NexusKeychain.shared.selectedModel) }
    var currentMood: String { isTyping ? "处理中" : "就绪" }
    var currentPlan: NexusTaskPlan? { activeEngine?.plan ?? runtime.currentPlan }
    var canResume: Bool { !isTyping && taskCheckpoint?.canResume == true }
    var canRetry: Bool { canResume && lastPrompt != nil && lastError != nil }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isTyping else { return }
        start(prompt, appendUser: true)
    }

    func retry() {
        guard canRetry, let prompt = lastPrompt else { return }
        if canResume { resume() } else { start(prompt, appendUser: false) }
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
        practice.stop()
        let startedAt = Date()
        activeStartedAt = startedAt
        activeRecoveryAttempt = !appendUser
        isTyping = true
        lastError = nil
        statusHint = "正在思考…"
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
        let skillIndex = NexusSkillRetrieval.index(skillSnapshot) + "\n" + practice.context + "\n" + cognitive.context
        var tools = NexusToolRegistry(control: cognitive)
        tools.register(NexusCausalTool()); tools.register(NexusDependencyTool())
        tools.register(NexusKnowledgeProposalTool(control: cognitive))
        if !skillSnapshot.isEmpty {
            tools.register(NexusSkillSearchTool(items: skillSnapshot))
            tools.register(NexusSkillReadTool(items: skillSnapshot))
        }
        tools.register(NexusShuyuTool())
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
            self.live.observe(progress.traces)
            saved.update(progress)
            self.taskCheckpoint = try self.checkpointStore.save(saved, redacting: key)
        }, onEvent: { [weak self] event in
            guard let self, self.runID == id else { return }
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
                self.statusHint = outcome.warning
                self.activeEngine = nil
                self.activeTask = nil
                let reply = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reply.isEmpty else { throw NexusError.invalidResponse }
                let message = ChatMessage(role: "assistant", content: reply)
                if var saved = self.taskCheckpoint {
                    saved.state = outcome.warning == nil ? .answered : .failed
                    saved.finalMessage = message
                    saved.warning = outcome.warning
                    saved.updatedAt = Date()
                    self.taskCheckpoint = try self.checkpointStore.save(saved, redacting: key)
                }
                self.messages.append(message)
                self.persist()
                self.runtime.append(.text(reply))
                self.runtime.append(.completed)
                self.live.finish(outcome.warning == nil ? .answered : .warning, message: outcome.warning ?? "本次答复已生成")
                self.evaluations.record(task: prompt, success: outcome.warning == nil, recovered: !appendUser && outcome.warning == nil,
                    verified: outcome.reviewPassed, latency: Date().timeIntervalSince(startedAt), recoveryAttempt: !appendUser)
                self.activeStartedAt = nil
            } catch {
                guard let self, self.runID == id, !Task.isCancelled else { return }
                self.isTyping = false
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
                self.live.finish(.failed, message: error.localizedDescription)
                self.runtime.fail(error.localizedDescription)
                self.evaluations.record(task: prompt, success: false, recovered: false, verified: false, latency: Date().timeIntervalSince(startedAt), recoveryAttempt: !appendUser)
                self.activeStartedAt = nil
            }
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do { try store.save(messages); return true }
        catch { lastError = "保存历史记录失败：\(error.localizedDescription)"; return false }
    }

    func cancel() {
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
        statusHint = "已停止"
        if lastError == nil { lastError = "任务已停止，可从保存的进度继续。" }
        runtime.cancel()
    }
}
