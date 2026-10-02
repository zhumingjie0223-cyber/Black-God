import Foundation
import CryptoKit

/// 不可信脚本静态审计：归一化后再匹配；拦截可留痕；放行危险命令仍记覆盖。
enum NexusScriptAudit {
    enum Level: String, Equatable, Sendable, Codable {
        case allow
        case caution
        case block
    }

    struct Verdict: Equatable, Sendable {
        let level: Level
        let reasons: [String]
        let normalized: String
        var summary: String {
            if reasons.isEmpty { return "审计：未发现高危模式" }
            let head = level == .block ? "审计拦截" : (level == .caution ? "审计提醒" : "审计")
            return head + "：" + reasons.joined(separator: "；")
        }
    }

    struct Event: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let at: Date
        let level: Level
        let reasons: [String]
        let digest: String
        let preview: String
        let overridden: Bool
    }

    static let confirmPhrase = "确认执行危险命令"
    private static let journalKey = "blackgod.sandbox.auditJournal"
    private static let journalLimit = 40

    static func allowDangerous(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "blackgod.sandbox.allowDangerous")
    }

    /// 折叠空白、去掉行尾反斜杠续行，降低简单混淆绕过。
    static func normalize(_ command: String) -> String {
        var text = command.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\\n", with: " ")
        text = text.replacingOccurrences(of: "\t", with: " ")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func inspect(_ command: String) -> Verdict {
        let text = normalize(command)
        var block: [String] = []
        var caution: [String] = []

        func match(_ pattern: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        if text.contains("\0") {
            block.append("含空字节")
        }
        if match(#"\$['\"]|\\x[0-9a-f]{2}|\\[0-7]{3}"#) {
            caution.append("含转义/拼接混淆痕迹")
        }

        // 只拦删根/通配根路径，避免误伤沙箱内 `rm -rf /workspace/foo`。
        if match(#"rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+|--force\s+)?(/|/\*|/\.\.)(\s|$)"#)
            || match(#"rm\s+-[a-zA-Z]*r[a-zA-Z]*\s+/(\s|$)"#) {
            block.append("疑似删除根目录或系统路径")
        }
        if match(#":\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:"#) || match(#"fork\s*bomb"#) {
            block.append("疑似进程炸弹")
        }
        if match(#"\b(mkfs|mke2fs|mkfs\.[a-z0-9]+)\b"#) {
            block.append("疑似格式化存储")
        }
        if match(#"\bdd\b.+\bof=/dev/"#) || match(#">\s*/dev/sd[a-z]"#) || match(#">\s*/dev/nvme"#) {
            block.append("疑似直接写入块设备")
        }
        if match(#"(curl|wget|fetch)\b[^|\n]*\|\s*(sh|bash|ash|zsh|dash)\b"#)
            || match(#"\b(sh|bash|ash)\s+-c\s+['\"]?\s*\$\("#) {
            block.append("疑似远程脚本管道执行")
        }
        if match(#"base64\s+(-d|--decode)[^|\n]*\|\s*(sh|bash|ash)\b"#) {
            block.append("疑似解码后直接执行")
        }
        if match(#"\b(shutdown|reboot|halt|poweroff|init\s+0|init\s+6)\b"#) {
            block.append("疑似关机或重启")
        }
        if match(#"\b(kill|pkill)\s+(-9\s+)?-1\b"#) || match(#"killall\s+-9"#) {
            block.append("疑似杀死全部进程")
        }
        if match(#">\s*/etc/"#) || match(#"tee\s+/etc/"#) || match(#"\bchmod\b.+/etc/"#) {
            block.append("疑似改写系统配置")
        }
        if match(#"\b(iptables|nft|ip6tables)\b"#) {
            block.append("疑似改动网络防火墙")
        }
        if match(#"\b(mount|umount|losetup)\b"#) {
            block.append("疑似挂载或卸载卷")
        }
        if match(#"\bnc\b.+\-e\b"#) || match(#"\bncat\b.+\-e\b"#)
            || match(#"/dev/tcp/"#) || match(#"bash\s+-i\s+>&\s*/dev/tcp/"#) {
            block.append("疑似反向外壳或原始套接字")
        }
        if match(#"\bchmod\s+(-R\s+)?777\s+/"#) {
            block.append("疑似对根路径放开权限")
        }

        if match(#"\brm\s+-[a-zA-Z]*r"#) {
            caution.append("递归删除")
        }
        if match(#"\bchmod\s+(-R\s+)?777\b"#) {
            caution.append("权限 777")
        }
        if match(#"\b(curl|wget)\b"#) {
            caution.append("外网下载（助手侧请优先用 http_fetch）")
        }
        if match(#"\bfind\b.+\-delete\b"#) {
            caution.append("find 删除")
        }
        if match(#"\bsudo\b"#) {
            caution.append("sudo（沙箱内通常无效）")
        }
        if match(#"\beval\b"#) || match(#"\bsource\s+/dev/stdin\b"#) {
            caution.append("动态求值")
        }

        if !block.isEmpty {
            return Verdict(level: .block, reasons: unique(block), normalized: text)
        }
        if !caution.isEmpty {
            return Verdict(level: .caution, reasons: unique(caution), normalized: text)
        }
        return Verdict(level: .allow, reasons: [], normalized: text)
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    /// 返回放行后的审计结论；拦截时抛出中文说明。危险开关放行仍会留痕。
    @discardableResult
    static func authorize(
        _ command: String,
        confirm: String? = nil,
        allowDangerous: Bool = false,
        defaults: UserDefaults = .standard
    ) throws -> Verdict {
        let verdict = inspect(command)
        if verdict.level != .block {
            if verdict.level == .caution {
                record(verdict, command: command, overridden: false, defaults: defaults)
            }
            return verdict
        }
        if allowDangerous {
            record(verdict, command: command, overridden: true, defaults: defaults)
            return verdict
        }
        let phrase = (confirm ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if phrase == confirmPhrase {
            record(verdict, command: command, overridden: true, defaults: defaults)
            return verdict
        }
        record(verdict, command: command, overridden: false, defaults: defaults)
        throw NexusReasoningError.execution(
            verdict.summary + "。默认拒绝执行。若你确认风险，请在参数 confirm 填「\(confirmPhrase)」，或在沙箱页打开「允许危险命令」（仍会留痕）。"
        )
    }

    static func recentEvents(in defaults: UserDefaults = .standard) -> [Event] {
        guard let data = defaults.data(forKey: journalKey),
              let list = try? JSONDecoder().decode([Event].self, from: data) else { return [] }
        return list
    }

    static func record(_ verdict: Verdict, command: String, overridden: Bool, defaults: UserDefaults = .standard) {
        let digest = SHA256.hash(data: Data(verdict.normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        let preview = String(normalize(command).prefix(96))
        var list = recentEvents(in: defaults)
        list.insert(Event(id: UUID(), at: Date(), level: verdict.level, reasons: verdict.reasons,
                          digest: String(digest.prefix(16)), preview: preview, overridden: overridden), at: 0)
        if list.count > journalLimit { list = Array(list.prefix(journalLimit)) }
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: journalKey)
        }
    }
}
