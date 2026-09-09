import Foundation
import Combine
import CryptoKit

struct NexusSkillPracticeResult: Codable, Identifiable {
    let id: UUID
    let skillID: String
    let fingerprint: String
    let caseID: String
    let title: String
    let passed: Bool
    let evidence: String
}
struct NexusSkillPracticeRound: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var state: String = "running"
    var results: [NexusSkillPracticeResult] = []
}

@MainActor
final class NexusSkillPractice: ObservableObject {
    private struct Archive: Codable { var version = 1; var rounds: [NexusSkillPracticeRound] }
    @Published private(set) var rounds: [NexusSkillPracticeRound] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var current = ""
    @Published var automatic: Bool {
        didSet { defaults.set(automatic, forKey: "blackgod.skills.practice.auto"); if !automatic { stop() } }
    }
    let live = NexusLiveExecution()
    private let url: URL
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var canWrite = true
    init(url: URL, defaults: UserDefaults = .standard) {
        self.url = url; self.defaults = defaults
        automatic = (defaults.object(forKey: "blackgod.skills.practice.auto") as? Bool) ?? true
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else { throw NexusError.invalidResponse }
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
                guard archive.version == 1, archive.rounds.count <= 30 else { throw NexusError.invalidResponse }
                rounds = archive.rounds
                for index in rounds.indices where rounds[index].state == "running" { rounds[index].state = "interrupted" }
                try persist(rounds)
            }
        } catch { canWrite = false; lastError = "演练记录读取失败，原文件保留：" + error.localizedDescription }
    }
    static func fingerprint(_ skill: NexusBuiltinSkill) -> String {
        let content = skill.skill.current.content
        let values = [skill.id, String(skill.skill.current.number), content.name, content.applicability, content.steps, content.verification] + skill.cases.flatMap { [$0.id, $0.program] }
        return SHA256.hash(data: try! JSONEncoder().encode(values)).map { String(format: "%02x", $0) }.joined()
    }
    func successfulRounds(_ skill: NexusBuiltinSkill) -> Int {
        let fingerprint = Self.fingerprint(skill)
        var count = 0
        for round in rounds.reversed() {
            let results = round.results.filter { $0.skillID == skill.id && $0.fingerprint == fingerprint }
            if results.isEmpty { continue }
            guard round.state == "completed", !skill.cases.isEmpty, results.count == skill.cases.count,
                  Set(results.map(\.caseID)) == Set(skill.cases.map(\.id)), results.allSatisfy(\.passed) else { break }
            count += 1
        }
        return count
    }
    func label(_ skill: NexusBuiltinSkill) -> String {
        if let missing = skill.missing { return missing }
        let count = successfulRounds(skill)
        return count >= 3 ? "当前版本通过\(count)轮本地样例演练" : "已通过\(count)/3轮 · 待巩固"
    }
    var context: String {
        "内置技能的本地演练记录（仅验证固定样例，不代表模型已学会或所有任务正确）：\n" + NexusBuiltinSkills.all.filter { $0.missing == nil }.map { $0.skill.current.content.name + "：" + label($0) }.joined(separator: "\n")
    }
    var due: Bool { automatic && canWrite && !isRunning && Date().timeIntervalSince(rounds.last?.startedAt ?? .distantPast) >= 900 }
    func start() {
        guard task == nil, !isRunning, canWrite else { return }
        task = Task { [weak self] in await self?.run() }
    }
    func stop() { task?.cancel() }
    func stopAndWait() async { let pending = task; pending?.cancel(); await pending?.value }
    func run(skills: [NexusBuiltinSkill] = NexusBuiltinSkills.all, tools override: NexusToolRegistry? = nil) async {
        guard !isRunning, canWrite else { return }
        isRunning = true; lastError = nil
        live.begin(goal: "内置技能演练")
        defer { isRunning = false; task = nil; current = "" }
        var round = NexusSkillPracticeRound(id: UUID(), startedAt: Date())
        let retained = Array(rounds.suffix(29))
        func save() throws { let next = retained + [round]; try persist(next); rounds = next }
        do {
            try save()
            var tools = override ?? NexusToolRegistry()
            if override == nil {
                tools.register(NexusCalculatorTool()); tools.register(NexusShuyuTool())
                if NexusLinuxTool.enabled { tools.register(NexusLinuxTool(workspace: NexusWorkspaceIdentity.id(for: "skill-practice"), onStart: { [weak self] in self?.live.append(.command, $0) }, onOutput: { [weak self] line, error in self?.live.append(error ? .error : .output, line) })) }
            }
            let runner = NexusShuyuRunTool(tools: tools, onTrace: { [weak self] in self?.live.observe([$0]) })
            var count = 0
            for skill in skills where skill.missing == nil {
                for test in skill.cases {
                    try Task.checkCancellation()
                    guard count < 24 else { throw NexusReasoningError.execution("本轮演练已达24个样例上限") }
                    count += 1; current = skill.skill.current.content.name + " · " + test.title
                    live.phase(current)
                    let result = await runner.execute(NexusToolCall(id: UUID(), name: "shuyu_execute", arguments: ["program": test.program]))
                    try Task.checkCancellation()
                    // Every practice action must have an explicit, matched expected result.
                    let details = try? JSONDecoder().decode([NexusShuyuStepResult].self, from: Data(result.output.utf8))
                    let passed = result.succeeded && details?.isEmpty == false && details?.allSatisfy({ $0.succeeded && $0.matched == true }) == true
                    round.results.append(NexusSkillPracticeResult(id: UUID(), skillID: skill.id, fingerprint: Self.fingerprint(skill), caseID: test.id, title: test.title, passed: passed, evidence: NexusEvidence.preview(result.output, limit: 1400)))
                    try save()
                    await Task.yield()
                }
            }
            round.state = "completed"; try save()
            live.finish(round.results.allSatisfy(\.passed) ? .answered : .warning, message: "本轮演练结束：\(round.results.filter(\.passed).count)/\(round.results.count)个样例通过")
        } catch {
            round.state = Task.isCancelled || error is CancellationError ? "cancelled" : "interrupted"
            lastError = round.state == "cancelled" ? "演练已停止" : error.localizedDescription
            live.finish(round.state == "cancelled" ? .cancelled : .failed, message: lastError ?? "演练中断")
            do { try save() } catch { lastError = "保存演练状态失败：" + error.localizedDescription }
        }
    }
    private func persist(_ value: [NexusSkillPracticeRound]) throws {
        let data = try JSONEncoder().encode(Archive(rounds: value))
        guard data.count <= 2_000_000 else { throw NexusReasoningError.execution("演练记录达到容量上限") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
