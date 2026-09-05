import Foundation

struct NexusToolCallParser {
    static func parse(_ text: String) -> [NexusToolCall] {
        guard let data = text.data(using: .utf8) else { return [] }
        if let calls = try? JSONDecoder().decode([NexusToolCall].self, from: data) { return calls }
        if let call = try? JSONDecoder().decode(NexusToolCall.self, from: data) { return [call] }
        return []
    }

    static func extract(from text: String) -> [NexusToolCall] {
        let blocks = text.components(separatedBy: "```json").dropFirst().compactMap { $0.components(separatedBy: "```").first }
        return blocks.flatMap(parse)
    }
}
