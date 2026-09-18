import Foundation
import JavaScriptCore

struct NexusShuyuProgram: Decodable {
    struct Action: Decodable {
        let id: String?
        let tool: String
        let arguments: [String: String]
        let expected: String?
    }
    let version: Int
    let actions: [Action]
}

/// 只加载随应用发布的枢语引擎，用户输入通过函数参数传递。
@MainActor
final class NexusShuyuEngine {
    static let shared = NexusShuyuEngine()
    private var context: JSContext?
    func invoke(_ operation: String, input: String) throws -> String {
        guard input.utf16.count <= 8192, !input.utf8.contains(0) else { throw NexusReasoningError.execution("枢语输入过长或包含无效字符") }
        if context == nil {
            guard let url = Bundle.main.url(forResource: "shuyu", withExtension: "js", subdirectory: "ShuyuRuntime"),
                  let next = JSContext() else { throw NexusReasoningError.execution("枢语运行资源缺失") }
            next.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            guard next.exception == nil, next.objectForKeyedSubscript("BlackGodShuyu")?.isObject == true else {
                throw NexusReasoningError.execution("枢语引擎初始化失败")
            }
            context = next
        }
        guard let context else { throw NexusError.invalidResponse }
        context.exception = nil
        guard let text = context.objectForKeyedSubscript("BlackGodShuyu")?.call(withArguments: [operation, input])?.toString(),
              context.exception == nil, let data = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NexusError.invalidResponse }
        guard result["ok"] as? Bool == true, let value = result["value"] else {
            throw NexusReasoningError.execution(result["error"] as? String ?? "枢语执行失败")
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    func compile(_ source: String) throws -> NexusShuyuProgram {
        let data = Data(try invoke("编译", input: source).utf8)
        let program = try JSONDecoder().decode(NexusShuyuProgram.self, from: data)
        guard program.version == 2, (1...8).contains(program.actions.count) else { throw NexusError.invalidResponse }
        return program
    }
    func prepare() {
        _ = try? invoke("容量", input: "")
    }
}

struct NexusShuyuTool: NexusTool {
    let name = "shuyu"
    let canReuseResult = true
    let usage = "Black God内置枢语。operation可选容量、解码、拉丁编号、汉译编号、检索、造词、组合、类比、邻近、一息、编译、规划、往返、质数；input为对应字符串。类比输入为JSON数组[词A,词B,词C]；邻近为词或JSON数组[词,数量]；一息为Unix秒或JSON数组[词,Unix秒]。词汇容量不是智能能力数量。"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        do {
            let value = try await NexusShuyuEngine.shared.invoke(call.arguments["operation"] ?? "", input: call.arguments["input"] ?? "")
            return NexusToolResult(callID: call.id, output: value, succeeded: true)
        } catch { return NexusToolResult(callID: call.id, output: error.localizedDescription, succeeded: false) }
    }
}

struct NexusShuyuStepResult: Codable {
    let id: String?
    let tool: String
    let output: String
    let succeeded: Bool
    let matched: Bool?
}

/// 有界执行，不暴露JavaScript或宿主对象；每个子工具仍检查当前权限。
struct NexusShuyuRunTool: NexusTool {
    let name = "shuyu_execute"
    let usage = "执行最多8行枢语。例：行：计算(\"12*3\") → \"36\"。支持计算、枢语、检索、邻近、一息、规划、核对、时间、执行。每个shell最多10秒；未知工具或语法会在执行前拒绝，失败或不符合→预期时停止。"
    let tools: NexusToolRegistry
    var onTrace: (@MainActor (NexusToolTrace) -> Void)? = nil
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        var results: [NexusShuyuStepResult] = []
        do {
            let program = try await NexusShuyuEngine.shared.compile(call.arguments["program"] ?? "")
            guard program.actions.allSatisfy({ tools.contains($0.tool) && ["calc", "shuyu", "shell_execute", "plan", "verify", "clock"].contains($0.tool) }) else {
                throw NexusReasoningError.execution("枢语程序包含当前未开放的工具，尚未执行")
            }
            for action in program.actions {
                try Task.checkCancellation()
                let inner = NexusToolCall(id: UUID(), name: action.tool, arguments: action.arguments)
                let value = await tools.execute(inner)
                try Task.checkCancellation()
                let matched = action.expected.map { value.output.trimmingCharacters(in: .whitespacesAndNewlines) == $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                results.append(NexusShuyuStepResult(id: action.id, tool: action.tool, output: NexusEvidence.preview(value.output, limit: 3000), succeeded: value.succeeded, matched: matched))
                await onTrace?(NexusToolTrace(stepID: call.id, round: results.count, call: inner, result: value.output, succeeded: value.succeeded, timestamp: Date()))
                if !value.succeeded || matched == false { break }
            }
            let ok = results.count == program.actions.count && results.allSatisfy { $0.succeeded && $0.matched != false }
            let data = try JSONEncoder().encode(results)
            return NexusToolResult(callID: call.id, output: String(decoding: data, as: UTF8.self), succeeded: ok)
        } catch {
            let prefix = (try? JSONEncoder().encode(results)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
            return NexusToolResult(callID: call.id, output: prefix + "\n" + error.localizedDescription, succeeded: false)
        }
    }
}

struct NexusPlanTool: NexusTool {
    let name = "plan"
    let canReuseResult = true
    let usage = "记录一个可检查的任务步骤标题，不执行外部操作。"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        let title = call.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return NexusToolResult(callID: call.id, output: "缺少 title", succeeded: false) }
        return NexusToolResult(callID: call.id, output: title, succeeded: true)
    }
}

struct NexusVerifyTool: NexusTool {
    let name = "verify"
    let canReuseResult = true
    let usage = "记录一条可检查的验收条件，不把模型自评当作已验证事实。"
    func execute(_ call: NexusToolCall) async -> NexusToolResult {
        let criterion = call.arguments["criterion"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !criterion.isEmpty else { return NexusToolResult(callID: call.id, output: "缺少 criterion", succeeded: false) }
        return NexusToolResult(callID: call.id, output: criterion, succeeded: true)
    }
}
