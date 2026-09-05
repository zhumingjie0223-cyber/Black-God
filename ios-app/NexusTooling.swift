import Foundation

struct NexusToolCall: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let arguments: [String: String]

    init(id: UUID = UUID(), name: String, arguments: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

struct NexusToolResult: Codable, Equatable {
    let callID: UUID
    let output: String
    let succeeded: Bool
}

/// 统一工具协议：结构化入参（`arguments` 字典）+ 结构化结果（`output` + `succeeded`）。
/// Runtime（受权限门约束）与 Executor（ASI 执行闭环）共用同一套工具抽象。
protocol NexusTool {
    var name: String { get }
    var usage: String { get }
    func execute(_ call: NexusToolCall) async -> NexusToolResult
}

extension NexusTool {
    var usage: String { "" }
}

/// 引用类型注册表：可在 `let` 常量上注册，供 Runtime 与 Executor 共享同一份工具集。
final class NexusToolRegistry {
    private var tools: [String: any NexusTool] = [:]

    init(_ tools: [any NexusTool] = []) {
        tools.forEach { self.tools[$0.name] = $0 }
    }

    func register(_ tool: any NexusTool) { tools[tool.name] = tool }
    func tool(named name: String) -> (any NexusTool)? { tools[name] }
    var isEmpty: Bool { tools.isEmpty }
    var allTools: [any NexusTool] { Array(tools.values) }
    var names: [String] { tools.keys.sorted() }

    /// 供模型阅读的工具清单（名称 + 用途）。
    var manifest: String {
        tools.values
            .sorted { $0.name < $1.name }
            .map { $0.usage.isEmpty ? "- \($0.name)" : "- \($0.name)：\($0.usage)" }
            .joined(separator: "\n")
    }

    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard let tool = tools[call.name] else {
            return NexusToolResult(callID: call.id, output: "未知工具：\(call.name)", succeeded: false)
        }
        return await tool.execute(call)
    }
}

struct EchoTool: NexusTool {
    let name = "echo"
    let usage = "原样返回文本。参数：text=要返回的文本"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        NexusToolResult(callID: call.id, output: call.arguments["text"] ?? "", succeeded: true)
    }
}

/// 工具执行回路：Runtime 侧使用，装载受权限门约束的工具集（含文件读写/占位 shell）。
struct NexusExecutionLoop {
    let registry: NexusToolRegistry
    init(registry: NexusToolRegistry = NexusToolRegistry()) { self.registry = registry }

    func installDefaults() {
        registry.register(EchoTool())
        registry.register(NexusReadFileTool())
        registry.register(NexusWriteFileTool())
        registry.register(NexusShellTool())
    }

    func run(_ call: NexusToolCall) async -> NexusToolResult { await registry.execute(call) }
}
