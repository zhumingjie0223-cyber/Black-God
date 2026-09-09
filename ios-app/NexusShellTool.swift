import Foundation

/// 当前工程尚未链接 Linux 用户态模拟器，也未配置远程执行服务。
/// iSH 类执行能力需要独立的内核、rootfs、进程管理与权限边界。
/// 此占位工具不注册到模型的原生工具列表。
struct NexusShellTool: NexusTool {
    let name = "shell"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        NexusToolResult(
            callID: call.id,
            output: "当前客户端未启用内置执行环境或远程执行后端。",
            succeeded: false
        )
    }
}
