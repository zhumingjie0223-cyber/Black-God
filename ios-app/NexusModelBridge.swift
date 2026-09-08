import Foundation

/// Bridges streaming callbacks while propagating cancellation to the network task.
struct NexusModelBridge {
    private final class ResponseState: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        private var finished = false
        private var cancelled = false
        private var continuation: CheckedContinuation<String, Error>?
        private var task: Task<Void, Never>?

        func begin(_ continuation: CheckedContinuation<String, Error>) {
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
        func install(_ task: Task<Void, Never>) {
            lock.lock()
            let stop = cancelled || finished
            if !stop { self.task = task }
            lock.unlock()
            if stop { task.cancel() }
        }
        func append(_ delta: String) {
            lock.lock(); defer { lock.unlock() }
            if !finished && !cancelled { text += delta }
        }
        func complete(_ error: Error? = nil) {
            lock.lock()
            guard !finished, let continuation else { lock.unlock(); return }
            finished = true
            self.continuation = nil
            task = nil
            let output = text
            // Cancelling the network task may synchronously invoke its completion
            // callback. Cancellation must win over that partial successful result.
            let completionError: Error? = cancelled ? CancellationError() : error
            lock.unlock()
            if let completionError { continuation.resume(throwing: completionError) }
            else if output.isEmpty { continuation.resume(throwing: NexusError.invalidResponse) }
            else { continuation.resume(returning: output) }
        }
        func cancel() {
            lock.lock()
            cancelled = true
            let running = task
            lock.unlock()
            running?.cancel()
            complete(CancellationError())
        }
    }

    static func complete(_ prompt: String, model: String? = nil) async throws -> String {
        try await complete(messages: [ChatMessage(role: "user", content: prompt)], model: model)
    }

    static func complete(messages: [ChatMessage], model: String? = nil) async throws -> String {
        let state = ResponseState()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                state.begin(continuation)
                let task = Task {
                    guard !Task.isCancelled else { state.complete(CancellationError()); return }
                    await NexusClient.shared.streamChat(
                        messages: messages, model: model,
                        onDelta: { state.append($0) },
                        onToolCall: { _ in },
                        onComplete: { state.complete() },
                        onError: { state.complete($0) }
                    )
                    state.complete()
                }
                state.install(task)
            }
        } onCancel: {
            state.cancel()
        }
    }
}
