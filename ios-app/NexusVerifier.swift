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

/// These checks detect incomplete output only. They do not establish factual
/// accuracy, satisfy semantic acceptance criteria, or override a justified refusal.
extension BasicNexusVerifier {
    func verify(goal: String, output: String) -> NexusVerdict {
        let report = NexusIndependentVerifier().verify(goal: goal, output: output)
        return NexusVerdict(passed: report.passed, reason: report.reason, checkedAt: Date())
    }
}

struct NexusIndependentVerifier {
    func verify(goal: String, output: String) -> NexusVerificationReport {
        let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaningful = cleanOutput.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0) || $0.properties.isEmojiPresentation
        }
        var activeFence: (character: Character, count: Int)?
        for line in cleanOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first, first == "`" || first == "~" else { continue }
            let count = trimmed.prefix(while: { $0 == first }).count
            guard count >= 3 else { continue }
            if let active = activeFence {
                if first == active.character, count >= active.count,
                   trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { activeFence = nil }
            } else {
                activeFence = (first, count)
            }
        }
        let checks = ["non_empty_content": meaningful,
                      "complete_code_fences": activeFence == nil,
                      "no_pending_tool_calls": NexusToolCallParser.parse(cleanOutput).isEmpty,
                      "bounded_output": cleanOutput.count <= 12000]
        let labels = ["non_empty_content": "缺少有效内容", "complete_code_fences": "代码块未闭合",
                      "no_pending_tool_calls": "尚有未处理的工具调用", "bounded_output": "输出超过长度上限"]
        let failed = checks.filter { !$0.value }.keys.sorted().map { labels[$0] ?? $0 }
        let reason = failed.isEmpty
            ? "结构完整性检查通过；不代表事实正确或任务成效已验证。"
            : "结构完整性检查未通过：" + failed.joined(separator: "、") + "。此检查不验证事实。"
        return NexusVerificationReport(passed: failed.isEmpty, checks: checks, reason: reason)
    }
}
