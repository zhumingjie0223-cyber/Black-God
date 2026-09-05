import Foundation

struct NexusToolResultBlock: Codable, Equatable {
    let type = "tool_result"
    let toolUseID: String
    let content: String
    let isError: Bool

    enum CodingKeys: String, CodingKey {
        case type, content
        case toolUseID = "tool_use_id"
        case isError = "is_error"
    }
}

struct NexusToolResultMessage: Codable, Equatable {
    let role = "user"
    let content: [NexusToolResultBlock]
}

struct NexusAssistantToolUseBlock: Codable, Equatable {
    let type = "tool_use"
    let id: String
    let name: String
    let input: [String: String]
}
