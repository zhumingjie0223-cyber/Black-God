import Foundation

struct NexusToolDefinition: Codable, Equatable {
    let name: String
    let description: String
    let inputSchema: [String: AnyCodable]

    enum CodingKeys: String, CodingKey { case name, description; case inputSchema = "input_schema" }
}

struct AnyCodable: Codable, Equatable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws { value = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); if let v = value as? String { try c.encode(v) } else { try c.encode("") } }
}

struct NexusToolCatalog {
    static let definitions = [
        NexusToolDefinition(name: "echo", description: "返回文本", inputSchema: ["type": AnyCodable("object")]),
        NexusToolDefinition(name: "read_file", description: "读取本地文件", inputSchema: ["type": AnyCodable("object")]),
        NexusToolDefinition(name: "write_file", description: "写入本地文件", inputSchema: ["type": AnyCodable("object")]),
        NexusToolDefinition(name: "shell", description: "执行本地命令", inputSchema: ["type": AnyCodable("object")])
    ]
}
