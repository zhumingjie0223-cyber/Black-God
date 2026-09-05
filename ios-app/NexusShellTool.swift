import Foundation

struct NexusShellTool: NexusTool {
    let name = "shell"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        guard let command = call.arguments["command"], !command.isEmpty else {
            return NexusToolResult(callID: call.id, output: "缺少 command", succeeded: false)
        }
        let process = Process()
        let out = Pipe()
        let err = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", command]
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            let timeout = Double(call.arguments["timeout"] ?? "30") ?? 30
            let deadline = Date().addingTimeInterval(min(max(timeout, 1), 120))
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning { process.terminate(); return NexusToolResult(callID: call.id, output: "命令超时并已终止", succeeded: false) }
            let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let result = (stdout + (stderr.isEmpty ? "" : "\n" + stderr)).trimmingCharacters(in: .whitespacesAndNewlines)
            return NexusToolResult(callID: call.id, output: result, succeeded: process.terminationStatus == 0)
        } catch {
            return NexusToolResult(callID: call.id, output: "命令执行失败：\(error.localizedDescription)", succeeded: false)
        }
    }
}
