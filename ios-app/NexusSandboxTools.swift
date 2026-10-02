import Foundation

/// 单工作区用户文件硬上限（不含系统硬链接镜像）。超限直接拒绝，不是软提醒。
enum NexusWorkspaceQuota {
    static let maxFiles = 200
    static let maxBytes: Int64 = 32 * 1024 * 1024
    static let maxSingleWrite = 2 * 1024 * 1024

    struct Snapshot: Equatable, Sendable {
        let files: Int
        let bytes: Int64
        var remainingFiles: Int { max(0, NexusWorkspaceQuota.maxFiles - files) }
        var remainingBytes: Int64 { max(0, NexusWorkspaceQuota.maxBytes - bytes) }
        var exhausted: Bool { files >= NexusWorkspaceQuota.maxFiles || bytes >= NexusWorkspaceQuota.maxBytes }
        var summary: String {
            "工作区 \(files)/\(NexusWorkspaceQuota.maxFiles) 个文件，\(byteText(bytes))/\(byteText(NexusWorkspaceQuota.maxBytes))"
        }
    }

    static func measure(at directory: URL?) throws -> Snapshot {
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else {
            return Snapshot(files: 0, bytes: 0)
        }
        var files = 0
        var bytes: Int64 = 0
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return Snapshot(files: 0, bytes: 0)
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
            if files > maxFiles + 5 { break }
        }
        return Snapshot(files: files, bytes: bytes)
    }

    static func enforce(adding bytes: Int64, creatingFile: Bool, at directory: URL?) throws {
        guard bytes >= 0, bytes <= maxSingleWrite else {
            throw NexusReasoningError.execution("单次写入不得超过 \(byteText(Int64(maxSingleWrite)))。")
        }
        let snap = try measure(at: directory)
        if creatingFile, snap.files >= maxFiles {
            throw NexusReasoningError.execution("工作区文件数已达硬上限 \(maxFiles)，请先清理后再写入。")
        }
        if snap.bytes + bytes > maxBytes {
            throw NexusReasoningError.execution("工作区容量硬上限 \(byteText(maxBytes))，当前已用 \(byteText(snap.bytes))，无法再写入 \(byteText(bytes))。")
        }
    }

    static func byteText(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}

struct NexusWorkspaceListTool: NexusTool {
    let name = "workspace_list"
    let usage = "列出当前沙箱工作区文件（相对 /workspace），只读。"
    let canReuseResult = true
    let workspace: UUID
    var isEnabled: () -> Bool = { NexusLinuxTool.enabled }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard isEnabled() else { return fail(call, "沙箱执行已关闭。") }
        do {
            let files = try await NexusLinuxRuntime.shared.listWorkspaceFiles(workspace: workspace)
            let host = NexusLinuxRuntime.shared.hostWorkspaceURL(for: workspace)
            let quota = try NexusWorkspaceQuota.measure(at: host)
            if files.isEmpty {
                return NexusToolResult(callID: call.id, output: "工作区为空。\n" + quota.summary, succeeded: true)
            }
            let list = files.map(\.path).joined(separator: "\n")
            return NexusToolResult(callID: call.id, output: quota.summary + "\n" + list, succeeded: true)
        } catch {
            return fail(call, error.localizedDescription)
        }
    }
    private func fail(_ call: NexusToolCall, _ text: String) -> NexusToolResult {
        NexusToolResult(callID: call.id, output: text, succeeded: false)
    }
}

struct NexusWorkspaceReadTool: NexusTool {
    let name = "workspace_read"
    let usage = "读取沙箱工作区文件。参数 path：相对路径；可选 max_chars（默认12000，最大50000）。"
    let canReuseResult = true
    let workspace: UUID
    var isEnabled: () -> Bool = { NexusLinuxTool.enabled }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard isEnabled() else { return fail(call, "沙箱执行已关闭。") }
        let path = NexusLinuxRuntime.sanitizeRelativePath(call.arguments["path"] ?? "")
        guard !path.isEmpty else { return fail(call, "缺少 path。") }
        let maxChars = min(max(Int(call.arguments["max_chars"] ?? "12000") ?? 12000, 1), 50_000)
        do {
            let data = try await NexusLinuxRuntime.shared.exportWorkspaceFile(path, workspace: workspace)
            var text = String(decoding: data, as: UTF8.self)
            var note = ""
            if text.utf8.count != data.count {
                note = "\n[提示：含非 UTF-8 字节，已按替换字符显示]"
            }
            if text.count > maxChars {
                text = String(text.prefix(maxChars))
                note += "\n[已截断到 \(maxChars) 字]"
            }
            return NexusToolResult(callID: call.id, output: text + note, succeeded: true)
        } catch {
            return fail(call, error.localizedDescription)
        }
    }
    private func fail(_ call: NexusToolCall, _ text: String) -> NexusToolResult {
        NexusToolResult(callID: call.id, output: text, succeeded: false)
    }
}

struct NexusWorkspaceWriteTool: NexusTool {
    let name = "workspace_write"
    let usage = "写入沙箱工作区文件。参数 path、content；受工作区硬配额约束，不能跨出 /workspace。"
    let workspace: UUID
    var isEnabled: () -> Bool = { NexusLinuxTool.enabled }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard isEnabled() else {
            return NexusToolResult(callID: call.id, output: "沙箱执行已关闭。", succeeded: false)
        }
        let path = NexusLinuxRuntime.sanitizeRelativePath(call.arguments["path"] ?? "")
        guard !path.isEmpty, let content = call.arguments["content"] else {
            return NexusToolResult(callID: call.id, output: "缺少 path 或 content。", succeeded: false)
        }
        guard let data = content.data(using: .utf8) else {
            return NexusToolResult(callID: call.id, output: "内容不是合法 UTF-8。", succeeded: false)
        }
        do {
            try await NexusLinuxRuntime.shared.importToWorkspace(data: data, named: path, workspace: workspace)
            let quota = try NexusWorkspaceQuota.measure(at: NexusLinuxRuntime.shared.hostWorkspaceURL(for: workspace))
            return NexusToolResult(callID: call.id, output: "已写入 \(path)\n" + quota.summary, succeeded: true)
        } catch {
            return NexusToolResult(callID: call.id, output: error.localizedDescription, succeeded: false)
        }
    }
}

/// 受控 HTTPS 抓取：在宿主侧下载后写入沙箱工作区，限制大小与重定向。
struct NexusHTTPFetchTool: NexusTool {
    let name = "http_fetch"
    let usage = "仅 HTTPS 抓取网页或文件并保存到沙箱工作区。参数 url、path；可选 max_bytes（默认524288，最大2097152）。不执行页面脚本。"
    let workspace: UUID
    var isEnabled: () -> Bool = { NexusLinuxTool.enabled }
    var networkAllowed: () -> Bool = { NexusHTTPFetchTool.networkEnabled }
    static var networkEnabled: Bool { networkEnabled(in: .standard) }
    static func networkEnabled(in defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: "blackgod.sandbox.network") as? Bool) ?? true
    }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard isEnabled() else {
            return NexusToolResult(callID: call.id, output: "沙箱执行已关闭。", succeeded: false)
        }
        guard networkAllowed() else {
            return NexusToolResult(callID: call.id, output: "沙箱联网已关闭。可在沙箱页重新开启。", succeeded: false)
        }
        guard let raw = call.arguments["url"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil else {
            return NexusToolResult(callID: call.id, output: "url 必须是 https:// 完整地址。", succeeded: false)
        }
        let path = NexusLinuxRuntime.sanitizeRelativePath(call.arguments["path"] ?? url.lastPathComponent)
        guard !path.isEmpty else {
            return NexusToolResult(callID: call.id, output: "缺少有效 path。", succeeded: false)
        }
        let maxBytes = min(max(Int(call.arguments["max_bytes"] ?? "524288") ?? 524288, 1), NexusWorkspaceQuota.maxSingleWrite)
        do {
            let data = try await Self.download(url, maxBytes: maxBytes)
            try await NexusLinuxRuntime.shared.importToWorkspace(data: data, named: path, workspace: workspace)
            let preview = String(decoding: data.prefix(400), as: UTF8.self)
            let quota = try NexusWorkspaceQuota.measure(at: NexusLinuxRuntime.shared.hostWorkspaceURL(for: workspace))
            return NexusToolResult(
                callID: call.id,
                output: "已保存 \(path)（\(data.count) 字节）\n\(quota.summary)\n预览：\n\(preview)",
                succeeded: true
            )
        } catch {
            return NexusToolResult(callID: call.id, output: error.localizedDescription, succeeded: false)
        }
    }

    static func download(_ url: URL, maxBytes: Int, session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("BlackGodSandbox/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NexusReasoningError.execution("无效的网络响应。")
        }
        guard (200...299).contains(http.statusCode) else {
            throw NexusReasoningError.execution("HTTP \(http.statusCode)")
        }
        if let length = http.expectedContentLength, length > maxBytes {
            throw NexusReasoningError.execution("远端声明大小 \(length) 超过上限 \(maxBytes) 字节。")
        }
        var data = Data()
        data.reserveCapacity(min(maxBytes, 64 * 1024))
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes {
                throw NexusReasoningError.execution("下载超过上限 \(maxBytes) 字节，已中止。")
            }
        }
        guard !data.isEmpty else { throw NexusReasoningError.execution("下载内容为空。") }
        return data
    }
}

extension NexusLinuxRuntime {
    func registerSandboxTools(into registry: inout NexusToolRegistry, workspace: UUID,
                              onStart: ((String) -> Void)? = nil,
                              onOutput: ((String, Bool) -> Void)? = nil,
                              onStatus: ((String) -> Void)? = nil) {
        registry.register(NexusLinuxTool(workspace: workspace, onStart: onStart, onOutput: onOutput, onStatus: onStatus))
        registry.register(NexusWorkspaceListTool(workspace: workspace))
        registry.register(NexusWorkspaceReadTool(workspace: workspace))
        registry.register(NexusWorkspaceWriteTool(workspace: workspace))
        registry.register(NexusHTTPFetchTool(workspace: workspace))
    }
}
