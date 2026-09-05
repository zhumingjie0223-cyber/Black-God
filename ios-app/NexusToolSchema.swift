import Foundation

struct NexusToolParameter: Codable, Equatable {
    var type = "string"
    let description: String
}

struct NexusToolInputSchema: Codable, Equatable {
    var type = "object"
    let properties: [String: NexusToolParameter]
    let required: [String]
    var additionalProperties = false
}

struct NexusToolDefinition: Codable, Equatable {
    let name: String
    let description: String
    let inputSchema: NexusToolInputSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct NexusToolCatalog {
    static let definitions: [NexusToolDefinition] = [
        definition("echo", "返回文本", ["text": "要返回的文本"], ["text"]),
        definition("read_file", "读取本地文件", ["path": "文件路径"], ["path"]),
        definition("write_file", "写入本地文件，须经批准", ["path": "文件路径", "content": "文件内容"], ["path", "content"]),
        definition("shell", "命令执行接口，须经批准并具备可用执行后端", ["command": "命令", "timeout": "秒数字符串，范围1至120"], ["command"])
    ]

    private static func definition(_ name: String, _ description: String,
                                   _ parameters: [String: String], _ required: [String]) -> NexusToolDefinition {
        NexusToolDefinition(name: name, description: description,
            inputSchema: NexusToolInputSchema(
                properties: parameters.mapValues { NexusToolParameter(description: $0) },
                required: required))
    }
}
