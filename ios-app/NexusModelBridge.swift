import Foundation

struct NexusModelBridge {
    static func complete(_ prompt: String, model: String? = nil) async throws -> String {
        try await complete(messages: [ChatMessage(role: "user", content: prompt)], model: model)
    }
    static func complete(messages: [ChatMessage], model: String? = nil) async throws -> String {
        try await NexusClient.shared.complete(messages: messages, model: model)
    }
}
