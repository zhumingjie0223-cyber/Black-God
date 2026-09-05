// ios-app/NexusModelBridge.swift
import Foundation

struct NexusModelBridge {
    static func complete(_ prompt: String, model: String? = nil) async throws -> String {
        let messages = [ChatMessage(role: "user", content: prompt)]
        return try await complete(messages: messages, model: model)
    }

    static func complete(messages: [ChatMessage], model: String? = nil) async throws -> String {
        final class Box: @unchecked Sendable {
            var text = ""
            var finished = false
            let lock = NSLock()
        }
        let box = Box()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            Task {
                await NexusClient.shared.streamChat(
                    messages: messages,
                    model: model,
                    onDelta: { delta in
                        box.lock.lock()
                        box.text += delta
                        box.lock.unlock()
                    },
                    onToolCall: { _ in },
                    onComplete: {
                        box.lock.lock()
                        defer { box.lock.unlock() }
                        guard !box.finished else { return }
                        box.finished = true
                        continuation.resume(returning: box.text)
                    },
                    onError: { error in
                        box.lock.lock()
                        defer { box.lock.unlock() }
                        guard !box.finished else { return }
                        box.finished = true
                        continuation.resume(throwing: error)
                    }
                )
                box.lock.lock()
                let alreadyFinished = box.finished
                if !alreadyFinished { box.finished = true }
                let text = box.text
                box.lock.unlock()
                if !alreadyFinished {
                    if text.isEmpty {
                        continuation.resume(throwing: NexusError.invalidResponse)
                    } else {
                        continuation.resume(returning: text)
                    }
                }
            }
        }
    }
}
