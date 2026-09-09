import Foundation

struct NexusPracticeCase: Identifiable {
    let id: String
    let title: String
    let program: String
}
struct NexusBuiltinSkill: Identifiable {
    let id: String
    let skill: NexusSkill
    let source: String
    let missing: String?
    let cases: [NexusPracticeCase]
}

enum NexusBuiltinSkills {
    private static func program(_ command: String, _ args: [String], expected: String) -> String {
        let encode: (String) -> String = { String(decoding: try! JSONEncoder().encode($0), as: UTF8.self) }
        return "行：\(command)(\(args.map(encode).joined(separator: ","))) → \(encode(expected))"
    }
    private static func shell(_ command: String, output: String) -> String {
        program("执行", [command], expected: "exit_code=0\nstdout:\n\(output)\nstderr:\n")
    }
    private static func make(_ suffix: String, _ name: String, conditions: String, steps: String, check: String, source: String, missing: String? = nil, cases: [(String, String)]) -> NexusBuiltinSkill {
        let id = UUID(uuidString: "10000000-0000-4000-8000-0000000000" + suffix)!
        let skill = NexusSkill(id: id, current: NexusSkillRevision(id: id, number: 1,
            content: NexusSkillContent(name: name, applicability: conditions, steps: steps, verification: check), savedAt: Date(timeIntervalSince1970: 0)), history: [], sourceTaskID: nil, sourceEvidenceIDs: [], builtinSource: source)
        return NexusBuiltinSkill(id: id.uuidString, skill: skill, source: source, missing: missing,
            cases: cases.enumerated().map { NexusPracticeCase(id: "\(suffix)-\($0.offset)", title: $0.element.0, program: $0.element.1) })
    }
    static let all: [NexusBuiltinSkill] = [
        make("01", "核心功能核验", conditions: "检查当前核心工具是否可用", steps: "确认已注册的工具，分别检查计算、枢语编解码、工作区临时文件读写。逐项记录实际结果，测试文件立即清理。没有的工具应报告缺失。", check: "对比明确的预期值和退出码；工具可用不等于所有业务正确。", source: "旧技能 core-smoke-test，适配当前iOS工具", cases: [
            ("计算", program("计算", ["12*3"], expected: "36")),
            ("枢语往返", program("枢语", ["往返", "神枢"], expected: "true")),
            ("文件读写清理", shell("f=$(mktemp); printf probe > \"$f\"; cat \"$f\"; rm \"$f\"", output: "probe"))]),
        make("02", "质数计算", conditions: "计算不超过10000的整数范围内全部质数", steps: "使用shuyu工具的质数操作，输入整数上界。结果从2开始，逐一检查能否被不超过平方根的整数整除，再返回列表和数量。当前无需Python。", check: "1不是质数；测试2、10、20的完整列表，不遗漏且不含合数。", source: "旧技能 python-prime-calculator，算法迁入枢语工具", cases: [
            ("最小质数", program("枢语", ["质数", "2"], expected: "[2]")),
            ("十以内", program("枢语", ["质数", "10"], expected: "[2,3,5,7]")),
            ("二十以内", program("枢语", ["质数", "20"], expected: "[2,3,5,7,11,13,17,19]"))]),
        make("03", "枢语编解码核验", conditions: "枢语造词、编号或汉译之间的对应检查", steps: "使用shuyu造词取得编号、拉丁词形和汉译；分别以拉丁编号和汉译编号反查，确认回到同一编号。需要执行时使用行：语句和明确的→验收结果。", check: "不同种子的两种反查均与原编号一致。词汇地址数量不代表智能水平。", source: "枢语v4.1权威引擎", cases: [
            ("神枢种子", program("枢语", ["往返", "神枢"], expected: "true")),
            ("品牌种子", program("枢语", ["往返", "Black God"], expected: "true")),
            ("混合字符", program("枢语", ["往返", "枢语-2026-🌱"], expected: "true"))]),
        make("04", "工作区文本统计", conditions: "在内置工作区处理文本、列表和数值汇总", steps: "按用户目标生成必要脚本，使用已有sh/awk工具。先用合成样例检查空输入、重复项和求和，再处理用户明确给定的数据。避免改变用户原文件，说明产物位置和限制。", check: "真实输出与已知统计结果一致；退出码为0；没有输入不能编造结果。", source: "Black God 内置执行环境", cases: [
            ("求和", shell("printf '%s\\n' 12 18 9 | awk '{s+=$1} END {print s}'", output: "39\n")),
            ("空输入", shell("printf '' | awk 'END {print NR}'", output: "0\n")),
            ("重复计数", shell("printf '%s\\n' apple apple banana | sort | uniq | wc -l", output: "2\n"))]),
        make("05", "录音转写与总结", conditions: "把录音转成文字并总结重点", steps: "先检查是否有录音输入和实际转写工具；缺少工具时说明缺口。不得伪造转写结果。", check: "必须对照实际音频和转写文本。", source: "旧技能 auto-gap-audio-transcription", missing: "尚未接入音频转写工具，不能演练或作为可用能力", cases: [])
    ]
    static var available: [NexusSkill] { all.filter { $0.missing == nil }.map(\.skill) }
}
