import Foundation

struct NexusToolCall: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let arguments: [String: String]
}

struct NexusToolResult: Codable, Equatable {
    let callID: UUID
    let output: String
    let succeeded: Bool
}

protocol NexusTool {
    var name: String { get }
    func execute(_ call: NexusToolCall) async -> NexusToolResult
}

struct NexusToolRegistry {
    private var tools: [String: any NexusTool] = [:]
    mutating func register(_ tool: any NexusTool) { tools[tool.name] = tool }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard let tool = tools[call.name] else {
            return NexusToolResult(callID: call.id, output: "未知工具：\(call.name)", succeeded: false)
        }
        return await tool.execute(call)
    }
}

struct EchoTool: NexusTool {
    let name = "echo"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        NexusToolResult(callID: call.id, output: call.arguments["text"] ?? "", succeeded: true)
    }
}

struct NexusExecutionLoop {
    private var registry: NexusToolRegistry
    init(registry: NexusToolRegistry = NexusToolRegistry()) { self.registry = registry }
    mutating func installDefaults() { registry.register(EchoTool()) }
    mutating func run(_ call: NexusToolCall) async -> NexusToolResult { await registry.execute(call) }
}
