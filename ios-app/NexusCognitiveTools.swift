import Foundation

/// Computes consequences of an explicitly supplied linear structural model.
/// It does not infer real-world causality from correlations.
struct NexusCausalTool: NexusTool {
    let name = "causal_model"
    let usage = "计算用户给定线性因果模型的干预结果，不从相关性推断因果。参数 model 为JSON，含 nodes数组，每项 name、bias、parents(变量:系数)，可选 interventions(变量:值)。最多30节点，必须无环。"
    struct Node: Codable { let name: String; let bias: Double; let parents: [String: Double] }
    struct Model: Codable { let nodes: [Node]; let interventions: [String: Double]? }
    static func evaluate(_ model: Model) throws -> [String: Double] {
        guard !model.nodes.isEmpty, model.nodes.count <= 30,
              Set(model.nodes.map(\.name)).count == model.nodes.count else { throw NexusReasoningError.execution("因果节点为空、重复或过多") }
        let names = Set(model.nodes.map(\.name))
        let interventions = model.interventions ?? [:]
        guard Set(interventions.keys).isSubset(of: names), interventions.values.allSatisfy(\.isFinite),
              model.nodes.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 60 && $0.bias.isFinite && $0.parents.values.allSatisfy(\.isFinite) && Set($0.parents.keys).isSubset(of: names) }) else { throw NexusReasoningError.execution("因果模型变量或数值无效") }
        // Validate the original graph even if an intervention would hide a cycle.
        var pending = model.nodes; var order: [Node] = []; var visited = Set<String>()
        while !pending.isEmpty {
            guard let index = pending.firstIndex(where: { Set($0.parents.keys).isSubset(of: visited) }) else { throw NexusReasoningError.execution("因果模型有环") }
            let node = pending.remove(at: index); order.append(node); visited.insert(node.name)
        }
        var values: [String: Double] = [:]
        for node in order {
            let value = interventions[node.name] ?? node.parents.keys.sorted().reduce(node.bias) { $0 + node.parents[$1]! * values[$1]! }
            guard value.isFinite else { throw NexusReasoningError.execution("因果计算溢出") }
            values[node.name] = value
        }
        return values
    }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        do {
            guard let input = call.arguments["model"], input.utf8.count <= 16000 else { throw NexusError.invalidResponse }
            let values = try Self.evaluate(JSONDecoder().decode(Model.self, from: Data(input.utf8)))
            let data = try JSONSerialization.data(withJSONObject: ["values": values, "scope": "仅在给定线性结构和干预假设成立时有效；不是现实因果证明"], options: [.sortedKeys])
            return .init(callID: call.id, output: String(decoding: data, as: UTF8.self), succeeded: true)
        } catch { return .init(callID: call.id, output: error.localizedDescription, succeeded: false) }
    }
}

struct NexusDependencyTool: NexusTool {
    let name = "dependency_plan"
    let usage = "校验长期计划依赖和关键路径。参数 tasks 为JSON数组，每项 id、duration(非负小时)、dependencies(ID数组)。不自动执行；最多50任务，假设资源无限并行。"
    struct Item: Codable { let id: String; let duration: Double; let dependencies: [String] }
    static func evaluate(_ tasks: [Item]) throws -> (order: [String], finish: [String: Double]) {
        let ids = Set(tasks.map(\.id))
        guard !tasks.isEmpty, tasks.count <= 50, ids.count == tasks.count,
              tasks.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 80 && $0.duration.isFinite && $0.duration >= 0 && Set($0.dependencies).isSubset(of: ids) }) else { throw NexusReasoningError.execution("任务标识、时长或依赖无效") }
        var remaining = tasks; var order: [String] = []; var finish: [String: Double] = [:]
        while !remaining.isEmpty {
            guard let i = remaining.firstIndex(where: { $0.dependencies.allSatisfy { finish[$0] != nil } }) else { throw NexusReasoningError.execution("任务存在循环依赖") }
            let item = remaining.remove(at: i)
            let value = (item.dependencies.compactMap { finish[$0] }.max() ?? 0) + item.duration
            guard value.isFinite else { throw NexusReasoningError.execution("计划时长溢出") }
            finish[item.id] = value; order.append(item.id)
        }
        return (order, finish)
    }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        do {
            guard let input = call.arguments["tasks"], input.utf8.count <= 16000 else { throw NexusError.invalidResponse }
            let result = try Self.evaluate(JSONDecoder().decode([Item].self, from: Data(input.utf8)))
            let data = try JSONSerialization.data(withJSONObject: ["order": result.order, "earliestFinishHours": result.finish, "minimumHours": result.finish.values.max() ?? 0, "scope": "给定时长、无资源冲突的下界；不是执行承诺。实际任务需检查点和重新估时。"], options: [.sortedKeys])
            return .init(callID: call.id, output: String(decoding: data, as: UTF8.self), succeeded: true)
        } catch { return .init(callID: call.id, output: error.localizedDescription, succeeded: false) }
    }
}
