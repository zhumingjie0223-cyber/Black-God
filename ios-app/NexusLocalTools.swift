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
    private(set) var lastError: String?
    @discardableResult
    func save(_ checkpoint: NexusCheckpoint) -> Bool {
        do {
            let data = try JSONEncoder().encode(checkpoint)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            lastError = nil
            return true
        } catch { lastError = "保存任务检查点失败：\(error.localizedDescription)"; return false }
    }
    func load() -> NexusCheckpoint? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try JSONDecoder().decode(NexusCheckpoint.self, from: Data(contentsOf: url)) }
        catch { lastError = "读取任务检查点失败：\(error.localizedDescription)"; return nil }
    }
    @discardableResult
    func clear() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            lastError = nil
            return true
        } catch { lastError = "删除任务检查点失败：\(error.localizedDescription)"; return false }
    }
}
