import Foundation

/// 含糊句先编译成任务卡。计划器只接收已解析的目标，不直接猜原话。
struct NexusIntentCard: Equatable {
    enum Risk: String, Equatable { case low, medium, high }

    let raw: String
    let goal: String
    let object: String?
    let constraints: [String]
    let success: String
    let missing: [String]
    let assumption: String?
    let risk: Risk
    let needsQuestion: Bool
    let question: String?
    let evidence: [String]

    var executableGoal: String {
        var lines = [goal]
        if let object, !object.isEmpty { lines.append("对象：\(object)") }
        if let assumption, !assumption.isEmpty { lines.append("假设：\(assumption)") }
        if !constraints.isEmpty { lines.append("约束：\(constraints.joined(separator: "；"))") }
        lines.append("成功条件：\(success)")
        if !evidence.isEmpty { lines.append("召回：\(evidence.joined(separator: "；"))") }
        return lines.joined(separator: "\n")
    }
}

struct NexusRecallHit: Equatable {
    let kind: String
    let title: String
    let score: Double
}

enum NexusIntentCompiler {
    static func compile(
        _ text: String,
        memories: [String] = [],
        files: [String] = [],
        skills: [String] = []
    ) -> NexusIntentCard {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let risk = riskOf(raw)
        let vague = isVague(raw)
        let hits = recall(raw, memories: memories, files: files, skills: skills)
        let top = hits.first
        let second = hits.dropFirst().first
        let tied = top != nil && second != nil && (top!.score - second!.score) < 0.12 && second!.score >= 0.34
        let object = top?.title
        let assumption: String?
        let needsQuestion: Bool
        let question: String?
        if vague && tied && risk != .low {
            assumption = nil
            needsQuestion = true
            question = "命中两个对象：\(top!.title)、\(second!.title)。要动哪一个？"
        } else if vague && top == nil && risk == .high {
            assumption = nil
            needsQuestion = true
            question = "这句没指定对象，而且会改动数据或对外发送。先说清楚要动哪一个。"
        } else if vague, let top {
            assumption = "按召回「\(top.title)」执行"
            needsQuestion = false
            question = nil
        } else if vague {
            assumption = "没有召回命中，只作说明，不开工具"
            needsQuestion = risk != .low
            question = risk == .low ? nil : "没对上已有记忆或文件。要处理哪一件？"
        } else {
            assumption = nil
            needsQuestion = false
            question = nil
        }
        let goal = assumption == nil ? raw : "\(raw) → \(assumption!)"
        return NexusIntentCard(
            raw: raw,
            goal: goal,
            object: object,
            constraints: constraints(for: risk, vague: vague),
            success: success(for: risk),
            missing: needsQuestion ? ["object"] : [],
            assumption: assumption,
            risk: risk,
            needsQuestion: needsQuestion,
            question: question,
            evidence: hits.prefix(3).map { "\($0.kind):\($0.title)" }
        )
    }

    static func recall(_ text: String, memories: [String], files: [String], skills: [String]) -> [NexusRecallHit] {
        let query = tokens(text)
        guard !query.isEmpty else { return [] }
        let pool = memories.map { ("memory", $0) } + files.map { ("file", $0) } + skills.map { ("skill", $0) }
        return pool.compactMap { kind, title -> NexusRecallHit? in
            let score = overlap(query, tokens(title))
            guard score >= 0.34 else { return nil }
            return NexusRecallHit(kind: kind, title: title, score: score)
        }
        .sorted { $0.score > $1.score }
    }

    static func isVague(_ text: String) -> Bool {
        let markers = ["那个", "这个", "上次", "弄一下", "处理一下", "看看", "帮我", "她", "它", "那份", "这份"]
        return markers.contains { text.contains($0) } || text.count <= 6
    }

    static func riskOf(_ text: String) -> NexusIntentCard.Risk {
        let high = ["删", "发送", "付款", "转账", "格式化", "shell", "执行", "推送", "清空"]
        let medium = ["改", "写", "保存", "上传", "安装"]
        if high.contains(where: { text.localizedCaseInsensitiveContains($0) }) { return .high }
        if medium.contains(where: { text.contains($0) }) { return .medium }
        return .low
    }

    private static func constraints(for risk: NexusIntentCard.Risk, vague: Bool) -> [String] {
        var items = ["不把模型自评当证据"]
        if vague { items.append("先写明假设再动手") }
        if risk == .high { items.append("高风险动作必须有唯一对象或用户确认") }
        return items
    }

    private static func success(for risk: NexusIntentCard.Risk) -> String {
        switch risk {
        case .low: return "给出可核对的结论，并标出依据来自哪一条召回或工具结果"
        case .medium: return "改动前写明对象，完成后用工具结果核对"
        case .high: return "未确认不执行；确认后只动命中对象，并保留可回滚记录"
        }
    }

    private static func tokens(_ text: String) -> Set<String> {
        let folded = text.lowercased()
        var bag: Set<String> = []
        let parts = folded.split { !$0.isLetter && !$0.isNumber }
        for part in parts where part.count >= 2 { bag.insert(String(part)) }
        let chars = Array(folded.filter { !$0.isWhitespace && $0 != "，" && $0 != "。" && $0 != "？" && $0 != "！" })
        if chars.count >= 2 {
            for index in 0..<(chars.count - 1) {
                bag.insert(String(chars[index...index + 1]))
            }
        }
        return bag
    }

    private static func overlap(_ query: Set<String>, _ candidate: Set<String>) -> Double {
        guard !query.isEmpty, !candidate.isEmpty else { return 0 }
        let hit = query.intersection(candidate).count
        return Double(hit) / Double(query.count)
    }
}
