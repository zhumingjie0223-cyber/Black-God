import Foundation

struct NexusLinuxTool: NexusTool {
    let name = "shell_execute"
    let usage = "在应用内 Alpine Linux 执行 shell 脚本。每个工作区有独立文件根目录，以非 root 用户执行；不能访问宿主应用凭据。参数 command；timeout 为可选秒数字符串，最多120。"
    let workspace: UUID
    var onStart: ((String) -> Void)? = nil
    var onOutput: ((String, Bool) -> Void)? = nil
    var isEnabled: () -> Bool = { NexusLinuxTool.enabled }
    static var enabled: Bool { enabled(in: .standard) }
    static func enabled(in defaults: UserDefaults) -> Bool {
        // New installs expose the embedded task capability; preserve an explicit opt-out.
        (defaults.object(forKey: "blackgod.linux.modelTools") as? Bool) ?? true
    }
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard isEnabled() else {
            return NexusToolResult(callID: call.id, output: "Linux 模型工具已关闭。", succeeded: false)
        }
        guard let command = call.arguments["command"], !command.isEmpty,
              let timeout = Double(call.arguments["timeout"] ?? "30") else {
            return NexusToolResult(callID: call.id, output: "缺少命令或超时参数无效。", succeeded: false)
        }
        do {
            onStart?(command)
            let result = try await NexusLinuxRuntime.shared.execute(command: command, timeout: timeout, workspace: workspace, onOutput: onOutput)
            let text = "exit_code=\(result.exitCode)\nstdout:\n\(result.output)\nstderr:\n\(result.errorOutput)"
                + (result.failure.map { "\nerror: " + $0 } ?? "")
            return NexusToolResult(callID: call.id, output: text, succeeded: result.succeeded)
        } catch {
            return NexusToolResult(callID: call.id, output: error.localizedDescription, succeeded: false)
        }
    }
}
