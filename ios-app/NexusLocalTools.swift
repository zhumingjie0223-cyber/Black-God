import Foundation

struct NexusReadFileTool: NexusTool {
    let name = "read_file"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard let path = call.arguments["path"], !path.isEmpty else {
            return NexusToolResult(callID: call.id, output: "缺少 path", succeeded: false)
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let text = String(decoding: data, as: UTF8.self)
            return NexusToolResult(callID: call.id, output: text, succeeded: true)
        } catch {
            return NexusToolResult(callID: call.id, output: "读取失败：\(error.localizedDescription)", succeeded: false)
        }
    }
}

struct NexusWriteFileTool: NexusTool {
    let name = "write_file"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard let path = call.arguments["path"], let content = call.arguments["content"] else {
            return NexusToolResult(callID: call.id, output: "缺少 path 或 content", succeeded: false)
        }
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
            return NexusToolResult(callID: call.id, output: "已写入：\(path)", succeeded: true)
        } catch {
            return NexusToolResult(callID: call.id, output: "写入失败：\(error.localizedDescription)", succeeded: false)
        }
    }
}

@MainActor
final class NexusCheckpointStore {
    private let url: URL
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("nexus-checkpoint.json")
    }
    func save(_ checkpoint: NexusCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        try? data.write(to: url, options: .atomic)
    }
    func load() -> NexusCheckpoint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NexusCheckpoint.self, from: data)
    }
    func clear() { try? FileManager.default.removeItem(at: url) }
}
