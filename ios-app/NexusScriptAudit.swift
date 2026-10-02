import Foundation

/// 不可信脚本静态审计：在进 Linux 之前拦截高危模式。
/// 默认拦截；助手可带口令单次放行，用户可在沙箱页打开「允许危险命令」。
enum NexusScriptAudit {
    enum Level: String, Equatable, Sendable {
        case allow
        case caution
        case block
    }

    struct Verdict: Equatable, Sendable {
        let level: Level
        let reasons: [String]
        var summary: String {
            if reasons.isEmpty { return "审计：未发现高危模式" }
            let head = level == .block ? "审计拦截" : (level == .caution ? "审计提醒" : "审计")
            return head + "：" + reasons.joined(separator: "；")
        }
    }

    static let confirmPhrase = "确认执行危险命令"

    static func allowDangerous(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "blackgod.sandbox.allowDangerous")
    }

    static func inspect(_ command: String) -> Verdict {
        let text = command
        var block: [String] = []
        var caution: [String] = []

        func match(_ pattern: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        if match(#"rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+|--force\s+)?(/|/\*|/\.\.)"#)
            || match(#"rm\s+-[a-zA-Z]*r[a-zA-Z]*\s+/($|\s)"#) {
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
            return Verdict(level: .block, reasons: unique(block))
        }
        if !caution.isEmpty {
            return Verdict(level: .caution, reasons: unique(caution))
        }
        return Verdict(level: .allow, reasons: [])
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    /// 返回放行后的审计结论；拦截时抛出中文说明。
    static func authorize(_ command: String, confirm: String? = nil, allowDangerous: Bool = false) throws -> Verdict {
        let verdict = inspect(command)
        guard verdict.level == .block else { return verdict }
        if allowDangerous { return verdict }
        let phrase = (confirm ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if phrase == confirmPhrase { return verdict }
        throw NexusReasoningError.execution(
            verdict.summary + "。默认拒绝执行。若你确认风险，请在参数 confirm 填「\(confirmPhrase)」，或在沙箱页打开「允许危险命令」。"
        )
    }
}
