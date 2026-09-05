import Foundation

struct NexusLoopResult {
    let messages: [ChatMessage]
    let toolResults: [NexusToolResult]
}

@MainActor
final class NexusAgentLoop {
    private let maxRounds: Int
    init(maxRounds: Int = 4) { self.maxRounds = max(1, maxRounds) }

    func appendToolResult(_ result: NexusToolResult, to messages: [ChatMessage]) -> [ChatMessage] {
        messages + [ChatMessage(role: "user", content: "[tool_result:\(result.callID)]\n\(result.output)")]
    }

    func calls(in text: String) -> [NexusToolCall] {
        NexusToolCallParser.extract(from: text)
    }

    var rounds: Int { maxRounds }
}
