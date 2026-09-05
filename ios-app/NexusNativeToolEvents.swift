import Foundation

struct NexusNativeToolEventParser {
    static func parse(_ object: [String: Any]) -> NexusToolCall? {
        guard object["type"] as? String == "content_block_start",
              let block = object["content_block"] as? [String: Any],
              block["type"] as? String == "tool_use",
              let name = block["name"] as? String,
              let idString = block["id"] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        let input = block["input"] as? [String: String] ?? [:]
        return NexusToolCall(id: id, name: name, arguments: input)
    }

    static func parseOpenAI(_ object: [String: Any]) -> NexusToolCall? {
        guard let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let calls = delta["tool_calls"] as? [[String: Any]],
              let function = calls.first?["function"] as? [String: Any],
              let name = function["name"] as? String else { return nil }
        return NexusToolCall(id: UUID(), name: name, arguments: [:])
    }
}
