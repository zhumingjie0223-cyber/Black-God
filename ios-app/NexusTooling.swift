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
    var usage: String { get }
    var canReuseResult: Bool { get }
    func execute(_ call: NexusToolCall) async -> NexusToolResult
}

extension NexusTool {
    var usage: String { name }
    var canReuseResult: Bool { false }
}

struct NexusToolRegistry {
    private var tools: [String: any NexusTool] = [:]
    private let control: NexusCognitiveControl?
    init(control: NexusCognitiveControl? = nil) { self.control = control }
    var isEmpty: Bool { tools.isEmpty }
    func contains(_ name: String) -> Bool { tools[name] != nil }
    func canReuseResult(_ name: String) -> Bool { tools[name]?.canReuseResult ?? false }
    var manifest: String {
        tools.keys.sorted().compactMap { tools[$0] }.map { "\($0.name): \($0.usage)" }.joined(separator: "\n")
    }
    mutating func register(_ tool: any NexusTool) { tools[tool.name] = tool }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        do {
            try Task.checkCancellation()
            let revision = try await control?.begin(call)
            guard let tool = tools[call.name] else { throw NexusReasoningError.execution("未知工具：\(call.name)") }
            let result = await tool.execute(call)
            if let control, let revision { try await control.finish(call, succeeded: result.succeeded, startedRevision: revision) }
            try Task.checkCancellation()
            return result
        } catch { return NexusToolResult(callID: call.id, output: error.localizedDescription, succeeded: false) }
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
    mutating func installDefaults() {
        registry.register(EchoTool())
        registry.register(NexusReadFileTool())
        registry.register(NexusWriteFileTool())
        registry.register(NexusShellTool())
    }
    mutating func run(_ call: NexusToolCall) async -> NexusToolResult { await registry.execute(call) }
}
