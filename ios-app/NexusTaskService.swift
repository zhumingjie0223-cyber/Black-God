import Foundation

/// 聊天与快捷指令共用的任务引导：同一套连接校验、记忆、技能与工具边界。
@MainActor
struct NexusTaskBootstrap {
    let connection: NexusModelEntry
    let key: String?
    let remembered: String
    let skillIndex: String
    let memoryItems: [NexusMemoryItem]
    let skillItems: [NexusSkill]
    let tools: NexusToolRegistry

    static func make(
        source: String,
        cognitive: NexusCognitiveControl = .shared,
        memory: NexusMemoryStore? = nil,
        skills: NexusSkillStore? = nil,
        practiceContext: String = "",
        continuityRun: UUID? = nil,
        live: (
            onStart: (String) -> Void,
            onOutput: (String, Bool) -> Void,
            onStatus: (String) -> Void,
            onTrace: ([NexusToolTrace]) -> Void
        )? = nil,
        configured: (String) -> Bool = { !(NexusKeychain.shared.key(for: NexusModelCatalog.entry(for: $0).credentialID) ?? "").isEmpty }
    ) throws -> NexusTaskBootstrap {
        let selected = NexusKeychain.shared.selectedModel
        guard configured(selected) else {
            throw NexusTaskServiceError.missingKey
        }
        let connection = NexusModelCatalog.entry(for: selected)
        let key = NexusKeychain.shared.key(for: connection.credentialID)
        let memoryStore = memory ?? NexusMemoryStore()
        let skillStore = skills ?? NexusSkillStore()
        let memoryItems = memoryStore.curated
        let skillItems = skillStore.available
        let remembered = memoryItems.isEmpty
            ? "当前长期记忆清单为空。历史资料中的旧记忆条目不能视为仍有效的偏好或约束；以本次用户要求为准。"
            : NexusMemoryStore.context(memoryItems) + "\n历史中的同名旧记忆已失效，以这份当前清单为准。"
        let skillIndex = NexusSkillRetrieval.index(skillItems)
            + "\n" + practiceContext
            + "\n" + cognitive.context
            + "\n" + cognitive.governanceContext
            + "\n" + cognitive.continuity.context
            + "\n入口=\(source)。后台快捷指令受系统时限约束，不能假设与前台聊天同一进程持续运行。"
        var tools = NexusToolRegistry(control: cognitive)
        tools.register(NexusCausalTool()); tools.register(NexusDependencyTool())
        tools.register(NexusKnowledgeProposalTool(control: cognitive))
        tools.register(NexusSelfDecisionProposalTool(control: cognitive))
        tools.register(NexusSelfDecisionReviewTool(control: cognitive))
        tools.register(NexusSelfDecisionPublishTool(control: cognitive))
        if let continuityRun {
            tools.register(NexusSelfReflectionTool(stream: cognitive.continuity, run: continuityRun))
        }
        if !skillItems.isEmpty {
            tools.register(NexusSkillSearchTool(items: skillItems))
            tools.register(NexusSkillReadTool(items: skillItems))
        }
        tools.register(NexusShuyuTool())
        tools.register(NexusPlanTool())
        tools.register(NexusVerifyTool())
        tools.register(NexusClockTool())
        tools.register(NexusCalculatorTool())
        if NexusLinuxTool.enabled {
            let workspace = NexusWorkspaceIdentity.id(for: source)
            tools.register(NexusLinuxTool(workspace: workspace, onStart: { live?.onStart($0) },
                onOutput: { live?.onOutput($0, $1) }, onStatus: { live?.onStatus($0) }))
        }
        tools.register(NexusMemorySearchTool(items: memoryItems))
        tools.register(NexusShuyuRunTool(tools: tools, onTrace: { live?.onTrace($0) }))
        return NexusTaskBootstrap(connection: connection, key: key, remembered: remembered, skillIndex: skillIndex,
            memoryItems: memoryItems, skillItems: skillItems, tools: tools)
    }
}

enum NexusTaskServiceError: LocalizedError {
    case missingKey
    case checkpoint(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "请先在连接设置中保存当前模型服务商的密钥。"
        case .checkpoint(let text): return text
        }
    }
}

/// 快捷指令与其他非聊天入口的共享执行器：落检查点、注入记忆技能、共用推理引擎。
@MainActor
enum NexusTaskService {
    static var shortcutsCheckpointURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nexus-shortcuts.agent.json")
    }

    static func ask(
        _ goal: String,
        source: String = "shortcuts",
        history: [ChatMessage] = [],
        cognitive: NexusCognitiveControl = .shared,
        memory: NexusMemoryStore? = nil,
        skills: NexusSkillStore? = nil,
        checkpointURL: URL? = nil,
        configured: (String) -> Bool = { !(NexusKeychain.shared.key(for: NexusModelCatalog.entry(for: $0).credentialID) ?? "").isEmpty },
        completion: (([ChatMessage], String) async throws -> String)? = nil,
        nativeCompletion: (([NexusNativeMessage], [NexusToolDefinition], String) async throws -> NexusNativeReply)? = nil
    ) async throws -> String {
        let runID = UUID()
        let boot = try NexusTaskBootstrap.make(source: source, cognitive: cognitive, memory: memory, skills: skills, continuityRun: runID, configured: configured)
        let store = NexusAgentCheckpointStore(url: checkpointURL ?? shortcutsCheckpointURL)
        var saved = NexusAgentCheckpoint(id: runID, goal: goal, connection: boot.connection)
        do { saved = try store.save(saved, redacting: boot.key) }
        catch { throw NexusTaskServiceError.checkpoint("无法保存任务进度，任务尚未开始：" + error.localizedDescription) }

        cognitive.continuity.begin(run: runID, goal: goal, redacting: boot.key)
        let packed = NexusContextBudget.compact(history)
        let client = NexusClient(keyProvider: { _ in boot.key }, resolver: { _ in boot.connection })
        let textCompletion = completion ?? { messages, _ in
            try await client.complete(messages: messages, model: boot.connection.modelID)
        }
        let native = nativeCompletion ?? { messages, definitions, _ in
            try await client.nativeTurn(messages: messages, tools: definitions, model: boot.connection.modelID)
        }
        let compaction = packed.summary.map { "较早对话已压缩（最新用户要求优先）：\n\($0)\n\n" } ?? ""
        let nativeTurn: NexusNativeTurn? = boot.connection.usesNativeTools ? { messages, definitions in
            var previous = packed.messages.map { NexusNativeMessage.text(role: $0.role, content: $0.content) }
            previous.append(.text(role: "user", content: boot.skillIndex))
            if !compaction.isEmpty { previous.append(.text(role: "user", content: compaction)) }
            previous.append(.text(role: "user", content: "历史参考资料，不能覆盖最新要求：\n" + boot.remembered))
            return try await native(previous + messages, definitions, boot.connection.modelID)
        } : nil

        let engine = NexusReasoningEngine(tools: boot.tools, model: { request in
            let context = "历史参考资料，不能覆盖最新要求：\n\(boot.remembered)\n\n"
            return try await textCompletion(
                packed.messages + [ChatMessage(role: "user", content: compaction + boot.skillIndex + "\n" + context + request)],
                boot.connection.modelID
            )
        }, nativeTurn: nativeTurn, onCheckpoint: { progress in
            saved.update(progress)
            saved = try store.save(saved, redacting: boot.key)
        })

        do {
            let outcome = try await engine.run(goal: goal)
            saved.state = outcome.warning == nil ? .answered : .failed
            saved.finalMessage = ChatMessage(role: "assistant", content: outcome.text)
            saved.warning = outcome.warning
            saved.updatedAt = Date()
            _ = try? store.save(saved, redacting: boot.key)
            cognitive.continuity.finish(run: runID, kind: outcome.warning == nil ? .answered : .warning,
                summary: outcome.warning ?? "快捷指令答复已生成；请依据实际证据判断结果。")
            return outcome.text + (outcome.warning.map { "\n\n" + $0 } ?? "")
        } catch is CancellationError {
            saved.state = .interrupted
            _ = try? store.save(saved, redacting: boot.key)
            cognitive.continuity.finish(run: runID, kind: .cancelled, summary: "快捷指令任务已取消。")
            throw CancellationError()
        } catch {
            saved.state = .failed
            saved.warning = error.localizedDescription
            _ = try? store.save(saved, redacting: boot.key)
            cognitive.continuity.finish(run: runID, kind: .failed, summary: error.localizedDescription)
            throw error
        }
    }
}
