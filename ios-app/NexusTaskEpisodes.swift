import Foundation

/// 情节只保留用户目标和实际工具指针，不将模型结论升级为长期事实。
struct NexusTaskEpisode: Codable, Identifiable {
    let id: UUID
    let goal: String
    let observedAt: Date
    let toolNames: [String]
    let evidenceIDs: [String]
    let objectPath: String?
    var objectTitle: String? = nil
    var observations: [NexusEvidenceRecord]? = nil

    var candidate: NexusRecallCandidate {
        NexusRecallCandidate(id: "task:" + id.uuidString.lowercased(), source: .taskSummary,
            title: objectTitle.map { $0 + " · " + String(goal.prefix(60)) } ?? String(goal.prefix(100)),
            text: "用户目标：\(goal)；已解析对象：\(objectTitle ?? "旧记录未保存名称")；已观测工具：\(toolNames.joined(separator: "、"))",
            objectPath: objectPath, observedAt: observedAt,
            provenance: "本机已保存工具记录；不包含模型生成的事实或偏好",
            aliases: [objectTitle, objectPath, objectPath.map { URL(fileURLWithPath: $0).lastPathComponent }].compactMap { $0 },
            evidencePointers: evidenceIDs)
    }
}

struct NexusTaskEpisodeStore {
    let url: URL
    static let maximumEpisodes = 100

    func load() throws -> [NexusTaskEpisode] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_048_576 else {
            throw failure("情节记录超出容量，保留原文件。")
        }
        let episodes = try JSONDecoder().decode([NexusTaskEpisode].self, from: Data(contentsOf: url))
        guard episodes.count <= Self.maximumEpisodes, Set(episodes.map(\.id)).count == episodes.count,
              episodes.allSatisfy({ episode in
                  guard !episode.goal.isEmpty, episode.goal.count <= 500, (episode.objectTitle?.count ?? 0) <= 200, !episode.evidenceIDs.isEmpty,
                        episode.evidenceIDs.count <= 24, let records = episode.observations else { return false }
                  return records.count == episode.evidenceIDs.count && Set(records.map(\.id)) == Set(episode.evidenceIDs) &&
                      records.allSatisfy { $0.succeeded && !$0.authorizationDenied }
              }) else {
            throw failure("情节记录格式无效，保留原文件。")
        }
        return episodes
    }

    func record(goal: String, card: NexusIntentCard?, traces: [NexusToolTrace], redacting secrets: [String] = []) throws {
        let observed = traces.filter { $0.succeeded && !$0.authorizationDenied &&
            !["plan", "verify", "knowledge_propose", "self_reflect"].contains($0.call.name) }
        guard !observed.isEmpty else { return }
        var episodes = try load()
        func redact(_ text: String) -> String {
            secrets.filter { !$0.isEmpty }.reduce(text) { $0.replacingOccurrences(of: $1, with: "[凭据已隐藏]") }
        }
        let originalPath = card?.objectPath
        let safePath = originalPath.flatMap { redact($0) == $0 ? $0 : nil }
        episodes.append(NexusTaskEpisode(id: UUID(), goal: String(redact(goal).prefix(500)), observedAt: Date(),
            toolNames: Array(Set(observed.map { $0.call.name })).sorted(),
            evidenceIDs: Array(observed.suffix(24).map { NexusEvidenceAudit.toolID($0.call.id) }),
            objectPath: safePath, objectTitle: card?.objectTitle.map { String(redact($0).prefix(200)) },
            observations: NexusEvidence.records(Array(observed.suffix(24))).map {
                NexusEvidenceRecord(id: $0.id, stepID: $0.stepID, tool: $0.tool, succeeded: $0.succeeded,
                    output: NexusEvidence.preview(redact($0.output), limit: 1200), authorizationDenied: $0.authorizationDenied, scope: $0.scope.map(redact))
            }))
        episodes = Array(episodes.suffix(Self.maximumEpisodes))
        let data = try JSONEncoder().encode(episodes)
        guard data.count <= 1_048_576 else { throw failure("情节记录超出容量。") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "BlackGod.TaskEpisodes", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@MainActor
enum NexusTaskRecall {
    /// 只枚举已存在的宿主工作区目录；为理解含糊指令不得先启动 Shell。
    static func candidates(goal: String, memories: [NexusMemoryItem],
                           knowledge: [NexusCognitiveControl.Knowledge], skills: [NexusSkill],
                           history: [ChatMessage], episodes: [NexusTaskEpisode], workspaceRoot: URL?) throws -> [NexusRecallCandidate] {
        var documents = NexusMemoryRetrieval.candidates(memories)
        documents += knowledge.filter { $0.confirmedAt != nil && $0.withdrawnAt == nil }.map {
            NexusRecallCandidate(id: "memory:knowledge:" + $0.id.uuidString.lowercased(), source: .confirmedMemory,
                title: $0.topic, text: $0.statement, observedAt: $0.confirmedAt ?? $0.recordedAt,
                provenance: $0.source, isConfirmed: true)
        }
        documents += episodes.map(\.candidate)
        if let workspaceRoot, FileManager.default.fileExists(atPath: workspaceRoot.path) {
            documents += try NexusRecallIndex.workspaceFileNames(root: workspaceRoot)
        }
        let conversation = conversationObjects(in: history)
        let directory = skills.map {
            NexusRecallCandidate(id: "skill:" + $0.id.uuidString.lowercased(), source: .skill,
                title: $0.current.content.name, text: $0.current.content.applicability,
                observedAt: $0.current.savedAt, provenance: "技能目录；读取不代表执行授权")
        }
        return NexusRecallIndex(candidates: documents).recall(query: goal, limit: 16,
            supplemental: conversation + directory)
    }

    static func explicitURLs(in goal: String) -> Set<String> {
        guard let detector = try? NSRegularExpression(pattern: "https://[^\\s<>\"，。；！？）]+") else { return [] }
        let text = goal as NSString
        return Set(detector.matches(in: goal, range: NSRange(location: 0, length: text.length)).compactMap {
            URL(string: text.substring(with: $0.range))?.absoluteString
        })
    }

    /// 最近原话仅提供已明确提及的文件对象；闲聊或整句操作指令不是可执行对象。
    static func conversationObjects(in history: [ChatMessage]) -> [NexusRecallCandidate] {
        let pattern = "(?:/workspace/)?(?:[A-Za-z0-9_\\-\\u4e00-\\u9fff]+/)*[A-Za-z0-9_\\-\\u4e00-\\u9fff]+\\.(?:txt|md|json|csv|html|js|py|swift|yaml|yml|pdf|xlsx?|docx?)(?![A-Za-z0-9_./\\-\\u4e00-\\u9fff])"
        guard let detector = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return history.filter { $0.role == "user" }.suffix(8).flatMap { message -> [NexusRecallCandidate] in
            let text = message.content as NSString
            var seen = Set<String>()
            return detector.matches(in: message.content, range: NSRange(location: 0, length: text.length)).compactMap { match -> NexusRecallCandidate? in
                // 拒绝从绝对路径、URL或穿越路径中截取一个看似安全的后缀。
                if match.range.location > 0 {
                    let previous = text.substring(with: NSRange(location: match.range.location - 1, length: 1))
                    if previous == "/" || previous == "." || previous == "~" || previous == "\\" { return nil }
                }
                let path = text.substring(with: match.range)
                guard let relative = NexusRecallCandidate.workspaceRelativePath(path), seen.insert(relative).inserted else { return nil }
                let title = URL(fileURLWithPath: relative).lastPathComponent
                let basename = URL(fileURLWithPath: relative).deletingPathExtension().lastPathComponent
                let pointer = "conversation:" + message.id.uuidString.lowercased()
                return NexusRecallCandidate(id: pointer + ":" + relative, source: .recentConversation,
                    title: title, text: "近期用户明确提及的工作区文件路径：" + relative,
                    objectPath: "/workspace/" + relative, observedAt: message.createdAt,
                    provenance: "近期用户原话中的明确文件路径；不是额外操作授权",
                    aliases: [relative, basename], evidencePointers: [pointer])
            }
        }
    }
}
