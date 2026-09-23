import Foundation
import SwiftUI

/// 从当天证据里记下一条规矩，并写成下次更新要守住的预备。
/// 不调用模型，不改权限，不把规矩当成已核对资料。
enum NexusDailyLessonDistiller {
    struct Draft: Equatable {
        let rule: String
        let evidence: String
        let updateNote: String
    }

    static let strongMarkers = ["记住", "别再", "以后", "下次", "错了", "不对"]
    static let ignoredTools: Set<String> = [
        "self_reflect", "self_decision_proposal", "self_decision_review", "self_decision_publish",
        "knowledge_propose", "knowledge_confirm", "knowledge_withdraw", "knowledge_restore"
    ]

    static func distill(userTexts: [String], failures: [(tool: String, date: Date)], existingRules: [String]) -> Draft? {
        if let sentence = latestTeachingSentence(in: userTexts) {
            guard !existingRules.contains(where: { normalize($0) == normalize(sentence) }) else { return nil }
            return Draft(
                rule: sentence,
                evidence: "来自用户原话",
                updateNote: "这次更新要守住用户原话。未核对前不当成已启用资料，不改权限，不把更新说成已经完美。"
            )
        }
        guard let failure = failures.last(where: { validToolName($0.tool) && !ignoredTools.contains($0.tool) }) else { return nil }
        let rule = "调用「\(failure.tool)」失败过。下次先核对参数和结果，失败不要当成完成。"
        guard !existingRules.contains(where: { normalize($0) == normalize(rule) }) else { return nil }
        return Draft(
            rule: rule,
            evidence: "工具返回失败",
            updateNote: "这次更新要补上「\(failure.tool)」失败后的核对与测试。没补上，就不能把这次更新说成准备好。"
        )
    }

    static func latestTeachingSentence(in texts: [String]) -> String? {
        for text in texts.reversed() {
            for sentence in sentences(text).reversed() {
                if let focused = focus(sentence) { return focused }
            }
        }
        return nil
    }

    static func sentences(_ text: String) -> [String] {
        var current = ""
        var result: [String] = []
        for character in text {
            if "。！？\n；".contains(character) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { result.append(piece) }
                current = ""
            } else {
                current.append(character)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    static func focus(_ sentence: String) -> String? {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !containsSecretRun(text) else { return nil }
        if let marker = strongMarkers.first(where: { text.contains($0) }) {
            return window(text, around: marker, limit: 120)
        }
        if text.count <= 40, text.contains("不要") { return text }
        return nil
    }

    static func window(_ text: String, around marker: String, limit: Int) -> String {
        guard text.count > limit, let range = text.range(of: marker) else { return String(text.prefix(limit)) }
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        let start = max(0, end - limit)
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(startIndex, offsetBy: min(limit, text.distance(from: startIndex, to: text.endIndex)))
        return String(text[startIndex..<endIndex])
    }

    static func containsSecretRun(_ text: String) -> Bool {
        var run = 0
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let token = (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value) || value == 45 || value == 95
            if token {
                run += 1
                if run >= 20 { return true }
            } else {
                run = 0
            }
        }
        return false
    }

    static func validToolName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(trimmed.count) else { return false }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value) || value == 95
        }
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

@MainActor
final class NexusDailyLearning: ObservableObject {
    struct Lesson: Codable, Identifiable, Equatable {
        let id: UUID
        let day: String
        let rule: String
        let evidence: String
        let updateNote: String
        var kept: Bool
        let createdAt: Date
    }

    struct State: Codable {
        var version = 1
        var lessons: [Lesson] = []
    }

    static let maximum = 30
    @Published private(set) var state = State()
    @Published private(set) var error: String?
    @Published private(set) var revision = 0
    private let url: URL
    private var writable = true

    init(url: URL) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 256_000 else { throw failure("每天学习记录过大。") }
                let loaded = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
                guard Self.valid(loaded) else { throw failure("每天学习记录格式不符合要求。") }
                state = loaded
            }
        } catch {
            writable = false
            state = State()
            self.error = "每天学习记录读不出来，已停用；原文件保留。"
        }
    }

    var kept: [Lesson] { state.lessons.filter(\.kept) }

    var context: String {
        guard writable else { return "每天学习记录读不出来，不能声称已经学过，也不能把这次更新说成已有预备。" }
        var lines = [
            "每天学习记下的规矩，每次更新前先读。它们来自用户纠正或工具失败，不是已核对事实，不增加授权，也不表示神枢已经完美。休眠时不学习；只有出现新证据时才记一条，一天最多一条。"
        ]
        let carried = kept.suffix(8)
        if carried.isEmpty {
            lines.append("更新预备：还没有可带着的规矩。没有预备时，不要声称这次更新已经准备好。")
        } else {
            lines.append("更新预备（每次更新先守住这些，守住了才算这次准备过）：")
            for item in carried {
                lines.append("\(item.day) \(item.rule) 预备：\(item.updateNote)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func learn(messages: [ChatMessage], traces: [NexusToolTrace] = [], now: Date = Date(), calendar: Calendar = .current) {
        guard writable else { return }
        let day = Self.dayKey(now, calendar: calendar)
        if let today = state.lessons.first(where: { $0.day == day }), !today.kept { return }
        let since = state.lessons.filter { $0.day != day }.map(\.createdAt).max() ?? .distantPast
        let users = messages.filter { $0.role == "user" && $0.createdAt > since }.suffix(40).map(\.content)
        let failures = traces.filter { !$0.succeeded }.map { (tool: $0.call.name, date: $0.timestamp) }
        let carried = state.lessons.filter { $0.kept && $0.day != day }.map(\.rule)
        guard let draft = NexusDailyLessonDistiller.distill(userTexts: Array(users), failures: failures, existingRules: carried) else { return }
        var next = state
        if let index = next.lessons.firstIndex(where: { $0.day == day }) {
            let old = next.lessons[index]
            guard NexusDailyLessonDistiller.normalize(old.rule) != NexusDailyLessonDistiller.normalize(draft.rule) else { return }
            next.lessons[index] = Lesson(
                id: old.id, day: day, rule: draft.rule, evidence: draft.evidence,
                updateNote: draft.updateNote, kept: true, createdAt: old.createdAt
            )
        } else {
            next.lessons.append(Lesson(
                id: UUID(), day: day, rule: draft.rule, evidence: draft.evidence,
                updateNote: draft.updateNote, kept: true, createdAt: now
            ))
        }
        if next.lessons.count > Self.maximum {
            next.lessons.removeFirst(next.lessons.count - Self.maximum)
        }
        do { try commit(next) } catch {}
    }

    func dismiss(_ id: UUID) throws {
        guard writable else { throw failure("每天学习记录读不出来，不能改。") }
        guard let index = state.lessons.firstIndex(where: { $0.id == id }) else { throw failure("这条规矩已经不在。") }
        var next = state
        next.lessons[index].kept = false
        try commit(next)
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func valid(_ state: State) -> Bool {
        guard state.version == 1, state.lessons.count <= maximum, Set(state.lessons.map(\.id)).count == state.lessons.count else { return false }
        return state.lessons.allSatisfy { lesson in
            lesson.day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
                && (1...120).contains(lesson.rule.count)
                && (1...80).contains(lesson.evidence.count)
                && (1...160).contains(lesson.updateNote.count)
        }
    }

    private func commit(_ next: State) throws {
        guard writable else { throw failure("每天学习记录读不出来，不能改。") }
        do {
            let data = try JSONEncoder().encode(next)
            guard data.count <= 256_000 else { throw failure("每天学习记录超过存储上限。") }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            state = next
            error = nil
            revision += 1
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "BlackGod.DailyLearning", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

struct NexusDailyLearningView: View {
    @ObservedObject var learning: NexusDailyLearning
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("怎么学") {
                    Text("一天最多留一条。只记你纠正过的话，或工具失败；同一天有新的纠正，就换成最新的。撤下之后，当天不再改记。不改权限，不当成已核对资料。每次更新前先看这些预备；没有预备，就不把更新说成准备好。学下去，也不自称完美。")
                }
                Section("更新预备 \(learning.kept.count)") {
                    if learning.kept.isEmpty {
                        Text("还没有。没有预备时，不能把更新说成已经准备好。")
                    }
                    ForEach(learning.kept) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.day).font(.caption)
                            Text(item.rule)
                            Text(item.updateNote).font(.caption)
                            Button("撤下这条") {
                                do { try learning.dismiss(item.id); message = nil }
                                catch { message = error.localizedDescription }
                            }
                            .accessibilityIdentifier("daily.learning.dismiss")
                        }
                    }
                }
                if let text = message ?? learning.error {
                    Section { Text(text).foregroundStyle(.red) }
                }
            }
            .navigationTitle("每天学习")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
