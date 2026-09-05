// ios-app/NexusVerifier.swift
import Foundation

struct NexusVerificationReport: Equatable {
    let passed: Bool
    let checks: [String: Bool]
    let reason: String
}

enum NexusKeywordExtractor {
    static let stopWords: Set<String> = [
        "的", "了", "是", "在", "我", "你", "他", "她", "它", "我们", "你们", "他们", "这", "那", "这个", "那个",
        "和", "与", "或", "及", "把", "被", "让", "给", "对", "从", "到", "为", "以", "于", "着", "过", "吗", "呢", "吧",
        "请", "帮", "帮我", "一下", "一个", "一些", "什么", "怎么", "如何", "为什么", "哪", "哪个", "哪些", "可以", "能",
        "要", "想", "需要", "应该", "就", "都", "也", "还", "很", "非常", "不", "没", "没有", "有", "会", "做", "写", "告诉",
        "a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "with", "is", "are", "was", "were", "be", "been",
        "i", "you", "he", "she", "it", "we", "they", "me", "my", "your", "this", "that", "these", "those", "please",
        "can", "could", "would", "should", "will", "do", "does", "did", "how", "what", "why", "which", "who", "when",
        "where", "help", "want", "need", "make", "write", "tell", "give", "about", "at", "by", "from", "as", "if", "then"
    ]

    static func keywords(from text: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        let lowered = text.lowercased()
        var latinBuffer = ""
        var cjkBuffer = ""

        func flushLatin() {
            if latinBuffer.count >= 2, !stopWords.contains(latinBuffer), !seen.contains(latinBuffer) {
                seen.insert(latinBuffer); result.append(latinBuffer)
            }
            latinBuffer = ""
        }
        func flushCJK() {
            guard !cjkBuffer.isEmpty else { return }
            let chars = Array(cjkBuffer)
            if chars.count == 1 {
                cjkBuffer = ""; return
            }
            if !stopWords.contains(cjkBuffer), chars.count <= 4, !seen.contains(cjkBuffer) {
                seen.insert(cjkBuffer); result.append(cjkBuffer)
            } else {
                var i = 0
                while i < chars.count {
                    let len = min(2, chars.count - i)
                    if len == 2 {
                        let bigram = String(chars[i..<i + 2])
                        if !stopWords.contains(bigram), !stopWords.contains(String(chars[i])) || !stopWords.contains(String(chars[i + 1])), !seen.contains(bigram) {
                            seen.insert(bigram); result.append(bigram)
                        }
                    }
                    i += 2
                }
            }
            cjkBuffer = ""
        }

        for scalar in lowered.unicodeScalars {
            let isCJK = (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
            if isCJK {
                flushLatin()
                cjkBuffer.unicodeScalars.append(scalar)
            } else if CharacterSet.alphanumerics.contains(scalar) {
                flushCJK()
                latinBuffer.unicodeScalars.append(scalar)
            } else {
                flushLatin(); flushCJK()
            }
        }
        flushLatin(); flushCJK()
        return result
    }
}

extension BasicNexusVerifier {
    func verify(goal: String, output: String) -> NexusVerdict {
        let now = Date()
        let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanOutput.isEmpty else {
            return NexusVerdict(passed: false, reason: "结果为空", checkedAt: now)
        }

        let refusalPrefixes = ["抱歉", "对不起", "无法", "我无法", "不知道", "我不知道", "sorry", "i cannot", "i can't", "i don't know"]
        let loweredOutput = cleanOutput.lowercased()
        if let hit = refusalPrefixes.first(where: { loweredOutput.hasPrefix($0) }) {
            return NexusVerdict(passed: false, reason: "结果以拒绝语「\(hit)」开头", checkedAt: now)
        }

        let keywords = NexusKeywordExtractor.keywords(from: cleanGoal)
        guard !keywords.isEmpty else {
            return NexusVerdict(passed: true, reason: "目标无可提取关键词，结果非空且非拒绝，视为通过", checkedAt: now)
        }

        let matched = keywords.filter { loweredOutput.contains($0) }
        let required = Int((Double(keywords.count) / 2.0).rounded(.up))
        let missing = keywords.filter { !matched.contains($0) }
        let passed = matched.count >= required

        if passed {
            return NexusVerdict(passed: true, reason: "关键词覆盖 \(matched.count)/\(keywords.count)（需≥\(required)）：命中「\(matched.joined(separator: "、"))」", checkedAt: now)
        } else {
            return NexusVerdict(passed: false, reason: "关键词覆盖不足 \(matched.count)/\(keywords.count)（需≥\(required)），缺失「\(missing.joined(separator: "、"))」", checkedAt: now)
        }
    }
}

struct NexusIndependentVerifier {
    func verify(goal: String, output: String) -> NexusVerificationReport {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmpty = !cleanOutput.isEmpty
        let hasError = ["出错了", "失败", "error", "timeout"].contains { cleanOutput.localizedCaseInsensitiveContains($0) }
        let keywords = NexusKeywordExtractor.keywords(from: cleanGoal)
        let lowered = cleanOutput.lowercased()
        let matched = keywords.filter { lowered.contains($0) }.count
        let hasGoalSignal = keywords.isEmpty || matched * 2 >= keywords.count
        let refusal = ["抱歉", "对不起", "无法", "不知道", "sorry", "i cannot", "i can't"].contains { lowered.hasPrefix($0) }
        let checks = ["non_empty": nonEmpty, "no_error_signal": !hasError, "goal_signal": hasGoalSignal, "no_refusal": !refusal]
        let allPassed = checks.values.allSatisfy { $0 }
        let failed = checks.filter { !$0.value }.keys.sorted().joined(separator: ", ")
        return NexusVerificationReport(passed: allPassed, checks: checks, reason: allPassed ? "独立验证通过（关键词 \(matched)/\(keywords.count)）" : "未通过检查：\(failed)")
    }
}
