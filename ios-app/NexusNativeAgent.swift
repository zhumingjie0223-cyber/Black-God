import Foundation

/// 服务商调用 ID 是不透明字符串，内部工具执行仍使用本地 UUID。
struct NexusNativeCall {
    let providerID: String
    let call: NexusToolCall
    var hasProviderID = true
}

struct NexusNativeReply {
    let text: String
    let calls: [NexusNativeCall]
    // 原样保留服务商要求回传的推理签名等字段；不展示或持久化。
    let assistant: [String: Any]
}

enum NexusNativeMessage {
    case text(role: String, content: String)
    case assistant(NexusNativeReply)
    case results([(NexusNativeCall, NexusToolResult)])
}

typealias NexusNativeTurn = ([NexusNativeMessage], [NexusToolDefinition]) async throws -> NexusNativeReply

/// 非流式工具回合必须接收完整且有效的消息后才能执行，避免半截参数触发动作。
enum NexusNativeCodec {
    static func body(model: NexusModelEntry, messages: [NexusNativeMessage], tools: [NexusToolDefinition]) throws -> Data {
        if model.providerType == .gemini || model.providerType == .responses { return try NexusAdditionalProtocols.body(model: model, messages: messages, tools: tools) }
        var wire: [[String: Any]] = []
        for message in messages {
            switch message {
            case .text(let role, let content):
                guard ["user", "assistant"].contains(role) else { throw NexusError.invalidResponse }
                wire.append(["role": role, "content": content])
            case .assistant(let reply): wire.append(reply.assistant)
            case .results(let results):
                if model.providerType == .anthropic {
                    wire.append(["role": "user", "content": results.map { item -> [String: Any] in
                        ["type": "tool_result", "tool_use_id": item.0.providerID,
                         "content": item.1.output, "is_error": !item.1.succeeded]
                    }])
                } else {
                    wire += results.map { ["role": "tool", "tool_call_id": $0.0.providerID,
                                           "content": ($0.1.succeeded ? "" : "工具失败：") + $0.1.output] }
                }
            }
        }
        guard !wire.isEmpty else { throw NexusError.invalidResponse }
        var body: [String: Any] = ["model": model.modelID, "stream": false, "messages": wire]
        if model.providerType == .anthropic { body["max_tokens"] = 4096 }
        if !tools.isEmpty {
            body["tools"] = try tools.map { definition -> [String: Any] in
                let schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(definition.inputSchema))
                if model.providerType == .anthropic {
                    return ["name": definition.name, "description": definition.description, "input_schema": schema]
                }
                return ["type": "function", "function": ["name": definition.name, "description": definition.description, "parameters": schema]]
            }
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        guard data.count <= 1_000_000 else { throw NexusError.apiError("工具上下文超过本次请求上限，请缩小任务。") }
        return data
    }

    static func decode(_ data: Data, type: NexusProviderType) throws -> NexusNativeReply {
        if type == .gemini || type == .responses { return try NexusAdditionalProtocols.decode(data, type: type) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] == nil else {
            throw NexusError.apiError("模型工具接口返回错误或无效消息。")
        }
        var calls: [NexusNativeCall] = []
        var ids = Set<String>()
        func add(_ id: Any?, _ name: Any?, _ input: Any?) throws {
            guard let id = id as? String, !id.isEmpty, id.utf8.count <= 512,
                  ids.insert(id).inserted, let name = name as? String, !name.isEmpty,
                  let arguments = input as? [String: String], calls.count < 8 else {
                throw NexusError.apiError("模型返回了无效、重复或过多的工具调用，尚未执行。")
            }
            calls.append(NexusNativeCall(providerID: id, call: NexusToolCall(id: UUID(), name: name, arguments: arguments)))
        }
        let text: String
        let assistant: [String: Any]
        if type == .anthropic {
            guard let blocks = object["content"] as? [[String: Any]], let stop = object["stop_reason"] as? String,
                  ["end_turn", "tool_use"].contains(stop) else {
                throw NexusError.apiError("模型工具响应未正常完成，尚未执行。")
            }
            for block in blocks where block["type"] as? String == "tool_use" {
                try add(block["id"], block["name"], block["input"])
            }
            guard (stop == "tool_use") == !calls.isEmpty else { throw NexusError.invalidResponse }
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            assistant = ["role": "assistant", "content": blocks]
        } else {
            guard let choices = object["choices"] as? [[String: Any]], choices.count == 1,
                  let message = choices[0]["message"] as? [String: Any],
                  let stop = choices[0]["finish_reason"] as? String, ["stop", "tool_calls"].contains(stop) else {
                throw NexusError.apiError("模型工具响应未正常完成，尚未执行。")
            }
            if let rawCalls = message["tool_calls"], !(rawCalls is NSNull) {
                guard let list = rawCalls as? [[String: Any]] else { throw NexusError.invalidResponse }
                for item in list {
                    guard item["type"] as? String == "function", let function = item["function"] as? [String: Any],
                          let raw = function["arguments"] as? String else { throw NexusError.invalidResponse }
                    try add(item["id"], function["name"], JSONSerialization.jsonObject(with: Data(raw.utf8)))
                }
            }
            guard (stop == "tool_calls") == !calls.isEmpty else { throw NexusError.invalidResponse }
            text = message["content"] as? String ?? message["refusal"] as? String ?? ""
            var replay = message
            replay["role"] = "assistant"
            assistant = replay
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else {
            throw NexusError.apiError("模型未返回回答或工具调用。")
        }
        return NexusNativeReply(text: text, calls: calls, assistant: assistant)
    }
}

extension NexusToolRegistry {
    /// 仅声明实际注册且有参数契约的工具，避免模型调用占位能力。
    var nativeDefinitions: [NexusToolDefinition] {
        let definitions: [(String, String, [String: String], [String])] = [
            ("shell_execute", "在独立文件工作区的 Alpine Linux 中执行脚本，返回 stdout、stderr 和退出码；不能访问宿主凭据，不支持持续后台进程", ["command": "shell 脚本", "timeout": "可选秒数字符串，默认30，最多120"], ["command"]),
            ("shuyu", "查询、编解码与检验Black God自己的枢语", ["operation": "容量/解码/拉丁编号/汉译编号/检索/造词/组合/编译/往返/质数", "input": "操作输入字符串；容量可为空"], ["operation"]),
            ("shuyu_execute", "执行枢语方言：最多4行，未知工具预先拒绝，失败停止", ["program": "例如 行：计算(\"12*3\") → \"36\""], ["program"]),
            ("clock", "查询当前日期时间", ["timezone": "可选 IANA 时区，如 Asia/Shanghai"], []),
            ("calc", "计算四则运算表达式", ["expression": "数学表达式，例如 (3+4)*2"], ["expression"]),
            ("skill_search", "检索用户保存的任务技能目录；只返回名称和条件摘要，不执行步骤", ["query": "任务关键词"], ["query"]),
            ("skill_read", "按目录ID读取技能的条件、步骤和验收方法；只是流程参考，仍需核实当前状态", ["id": "技能UUID"], ["id"]),
            ("memory_search", "检索用户此前明确说过的内容", ["query": "检索内容"], ["query"]),
            ("causal_model", NexusCausalTool().usage, ["model": "线性结构模型JSON"], ["model"]),
            ("dependency_plan", NexusDependencyTool().usage, ["tasks": "任务依赖JSON数组"], ["tasks"]),
            ("knowledge_propose", "提交知识候选，必须经用户核对后才可启用；不改变权限", ["topic": "主题", "statement": "内容，区分推断与观测", "source": "可核对的来源"], ["topic", "statement", "source"])
        ]
        return definitions.filter { contains($0.0) }.map {
            NexusToolDefinition(name: $0.0, description: $0.1,
                inputSchema: NexusToolInputSchema(properties: $0.2.mapValues { NexusToolParameter(description: $0) }, required: $0.3))
        }
    }

    func validateNative(_ call: NexusToolCall) -> String? {
        guard let schema = nativeDefinitions.first(where: { $0.name == call.name })?.inputSchema else { return "未知或未开放的工具：\(call.name)" }
        guard Set(call.arguments.keys).isSubset(of: Set(schema.properties.keys)),
              schema.required.allSatisfy({ !(call.arguments[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              call.arguments.values.allSatisfy({ $0.utf8.count <= 8192 }) else { return "参数不符合工具定义，请修正后重试。" }
        return nil
    }
}
