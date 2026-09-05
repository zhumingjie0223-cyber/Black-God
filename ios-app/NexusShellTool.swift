import Foundation

/// iOS 安全边界：App Store 版 App 不直接执行任意 shell 命令。
/// `Process` / `NSTask` 在 iOS 上不存在，且审核禁止任意代码执行。
/// 此工具保留为神枢工具总线的占位，明确返回环境限制。
struct NexusShellTool: NexusTool {
    let name = "shell"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        NexusToolResult(
            callID: call.id,
            output: "当前 iOS 客户端不提供 shell 执行环境。命令执行能力仅存在于服务端/开发环境。",
            succeeded: false
        )
    }
}
