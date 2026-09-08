#if NEXUS_STORAGE_TESTS
import Foundation

// 本测试直接编译生产存储与计划类型。下面只隔离未测试的执行器和系统钥匙串边界，
// 任何意外调用都立即失败，确保测试不会修改开发者的真实密钥或调用模型。
struct NexusToolTrace: Codable {}
extension BasicNexusVerifier {
    func verify(goal: String, output: String) -> NexusVerdict { fatalError("存储测试不应运行验证器") }
}
final class NexusKeychain {
    static let shared = NexusKeychain()
    func wipeAll() -> [String] { fatalError("存储测试必须注入隔离的钥匙串操作") }
}

@main
struct NexusStorageTests {
    @MainActor
    static func main() throws {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError("存储测试失败：\(message)") }
            passed += 1
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-storage-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func folder(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let memoryDirectory = try folder("memory")
        let memory = NexusMemoryStore(directory: memoryDirectory)
        check(memory.items.isEmpty && memory.lastError == nil, "新存储没有伪造错误")
        check(!memory.remember(" \n "), "拒绝空记忆")
        check(memory.remember("  I prefer green tea  "), "记忆落盘")
        let originalID = memory.items[0].id
        check(memory.remember("i  PREFER green tea", confidence: .nan), "大小写和空格归一去重")
        check(memory.items.count == 1 && memory.items[0].id == originalID, "去重保留编号")
        check(memory.items[0].confidence == 0.8, "无效置信度修正")
        let restored = NexusMemoryStore(directory: memoryDirectory)
        check(restored.items == memory.items, "旧格式记忆完整重载")
        let permissions = try FileManager.default.attributesOfItem(atPath: memoryDirectory.appendingPathComponent("nexus-memory.json").path)[.posixPermissions] as? NSNumber
        check(permissions?.intValue == 0o600, "存储文件只允许当前用户读取")
        check(memory.remove(originalID) && NexusMemoryStore(directory: memoryDirectory).items.isEmpty, "删除持久化")
        check(memory.remember(String(repeating: "字", count: 4500)) && memory.items[0].text.count == 4000, "单条最多4000字")
        check(!memory.remember("过期内容", expiresAt: Date(timeIntervalSinceNow: -1)), "拒绝立即过期的记忆")
        check(memory.clear(), "清空记忆")
        for i in 0..<205 { check(memory.remember("收藏条目 \(i)"), "批量记忆可持久化 \(i)") }
        check(memory.items.count == 200 && !memory.items.contains(where: { $0.text == "收藏条目 0" }), "最多保留200条最新记忆")
        check(NexusMemoryStore(directory: memoryDirectory).items.count == 200, "重载也保持容量边界")

        let searchDirectory = try folder("search")
        let search = NexusMemoryStore(directory: searchDirectory)
        search.remember("我喜欢喝无糖拿铁咖啡", confidence: 1)
        search.remember("我住在金边，喜欢旅行")
        search.remember("I enjoy the art museum.")
        search.remember("A birthday party is next week.")
        check(search.search("记得我喜欢喝什么咖啡吗").map(\.text) == ["我喜欢喝无糖拿铁咖啡"], "中文自然句检索具体主题")
        check(search.search("Tell me about ART").map(\.text) == ["I enjoy the art museum."], "英文整词匹配不误中party")
        check(search.search("").isEmpty && search.search("请帮我一下").isEmpty, "空查询与泛词不暴露全部记忆")
        check(search.search("咖啡", limit: -1).isEmpty, "负数数量不会崩溃")
        for i in 0..<12 { search.remember("coffee preference \(i)") }
        check(search.search("coffee", limit: 100).count == 8, "检索最多8条")
        search.clear()
        for i in 0..<3 { search.remember("coffee \(i) " + String(repeating: "内容", count: 1900)) }
        check(search.search("coffee").reduce(0, { $0 + $1.text.count }) <= 6000, "检索注入上下文不超过6000字")

        let legacyDirectory = try folder("legacy")
        let now = Date()
        let oldItems = [
            NexusMemoryItem(id: UUID(), text: "旧格式内容", kind: "episodic", source: "runtime", confidence: 0.7, createdAt: now, expiresAt: nil),
            NexusMemoryItem(id: UUID(), text: "已过期", kind: "episodic", source: "runtime", confidence: 0.8, createdAt: now, expiresAt: now.addingTimeInterval(-1))
        ]
        try JSONEncoder().encode(oldItems).write(to: legacyDirectory.appendingPathComponent("nexus-memory.json"))
        check(NexusMemoryStore(directory: legacyDirectory).items.map(\.text) == ["旧格式内容"], "兼容已有格式并过滤过期内容")
        let badDirectory = try folder("damaged")
        let badFile = badDirectory.appendingPathComponent("nexus-memory.json")
        try Data("invalid JSON".utf8).write(to: badFile)
        let badMemory = NexusMemoryStore(directory: badDirectory)
        check(badMemory.lastError != nil && !badMemory.remember("不能覆盖"), "损坏文件错误可见并阻止覆盖")
        let preservedBadFile = try String(contentsOf: badFile, encoding: .utf8)
        check(preservedBadFile == "invalid JSON", "保留损坏原文件可恢复")
        check(badMemory.clear() && badMemory.remember("重新开始"), "明确清除后可再次保存")

        let blocked = root.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blocked)
        let unwritable = NexusMemoryStore(directory: blocked)
        check(!unwritable.remember("无法写入") && unwritable.lastError != nil && unwritable.items.isEmpty, "写入失败不伪装成内存已保存")

        let historyDirectory = try folder("history")
        let history = NexusTaskHistoryStore(directory: historyDirectory)
        let taskID = UUID()
        let plan = NexusTaskPlan(id: UUID(), goal: "计算一加一", steps: [NexusTaskStep(title: "计算", status: .passed, result: "2")], createdAt: now)
        let trace = NexusTaskHistoryTrace(stepID: plan.steps[0].id, round: 1, name: "calc", arguments: ["expr": "1+1"], result: "2", succeeded: true, timestamp: now)
        check(history.record(id: taskID, goal: "计算一加一", model: "test-model", plan: plan, toolTraces: [trace], result: "结果是2", status: .completed, createdAt: now), "历史记录写入")
        let loadedHistory = NexusTaskHistoryStore(directory: historyDirectory)
        check(loadedHistory.records == history.records && loadedHistory.records[0].plan == plan, "历史计划与工具完整重载")
        check(history.record(id: taskID, goal: "计算一加一", model: "test-model", result: "已取消", status: .cancelled), "相同任务更新")
        check(history.records.count == 1 && history.records[0].createdAt == now && history.records[0].status == .cancelled, "更新保留开始时间且不重复")
        for i in 0..<55 { history.record(goal: "任务 \(i)", model: "test-model", result: "完成", status: .completed) }
        check(history.records.count == 50 && !history.records.contains(where: { $0.id == taskID }), "历史最多50次任务")
        let latest = history.records[0].id
        check(history.remove(latest) && !NexusTaskHistoryStore(directory: historyDirectory).records.contains(where: { $0.id == latest }), "删除单条历史持久化")
        history.record(goal: "长结果", model: "test-model", result: String(repeating: "文", count: 13000), status: .failed)
        check(history.records[0].result.count == 12000, "历史结果限制长度")
        let badHistoryDirectory = try folder("bad-history")
        let badHistoryFile = badHistoryDirectory.appendingPathComponent("nexus-task-history.json")
        try Data("bad".utf8).write(to: badHistoryFile)
        let badHistory = NexusTaskHistoryStore(directory: badHistoryDirectory)
        check(badHistory.lastError != nil && !badHistory.record(goal: "不能覆盖", model: "test", result: "", status: .failed), "历史损坏禁止静默覆盖")

        let evaluationDirectory = try folder("evaluation")
        let evaluation = NexusEvaluationStore(directory: evaluationDirectory)
        check(evaluation.record(task: "任务", success: true, recovered: false, verified: true, latency: 2), "评估写入")
        check(evaluation.record(task: "任务2", success: false, recovered: true, verified: false, latency: .infinity), "无效延迟归零")
        let loadedEvaluation = NexusEvaluationStore(directory: evaluationDirectory)
        check(loadedEvaluation.records.count == 2 && loadedEvaluation.successRate == 0.5 && loadedEvaluation.averageLatency == 1, "旧评估格式兼容与统计")

        let wipeDirectory = try folder("wipe")
        let wipeMemory = NexusMemoryStore(directory: wipeDirectory)
        let wipeHistory = NexusTaskHistoryStore(directory: wipeDirectory)
        let wipeEvaluation = NexusEvaluationStore(directory: wipeDirectory)
        wipeMemory.remember("清除目标")
        wipeHistory.record(goal: "清除目标", model: "test", result: "done", status: .completed)
        wipeEvaluation.record(task: "清除目标", success: true, recovered: false, verified: true, latency: 0)
        let workspace = wipeDirectory.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: workspace.appendingPathComponent("note.txt"))
        var keychainCalled = false
        let errors = NexusDataReset.wipeAll(directory: wipeDirectory, keychainWipe: { keychainCalled = true; return [] })
        check(errors.isEmpty && keychainCalled, "清除汇总钥匙串与文件操作")
        check(wipeMemory.items.isEmpty && wipeHistory.records.isEmpty && wipeEvaluation.records.isEmpty, "清除后所有内存列表立即清空")
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: wipeDirectory.path)
        check(remainingFiles.isEmpty, "任务工作区与持久化文件全部删除")
        check(wipeMemory.remember("清除后新记忆"), "清除后存储仍可用")
        let wipeErrors = NexusDataReset.wipeAll(directory: blocked, keychainWipe: { ["模拟钥匙串失败"] })
        check(wipeErrors.count == 2 && wipeErrors.contains("模拟钥匙串失败"), "独立收集钥匙串与文件目录错误")
        check(NexusDataReset.wipeAll(directory: root.appendingPathComponent("missing"), keychainWipe: { [] }).isEmpty, "不存在的数据目录可重复清除")
        print("存储测试通过：\(passed) 项断言；全程临时目录，无线上请求，无真实钥匙串读写。")
    }
}
#endif
