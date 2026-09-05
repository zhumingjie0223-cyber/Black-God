import Foundation

struct NexusRetryPolicy {
    let maxAttempts: Int
    let baseDelayNanoseconds: UInt64
    init(maxAttempts: Int = 2, baseDelayNanoseconds: UInt64 = 300_000_000) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelayNanoseconds = baseDelayNanoseconds
    }
}

@MainActor
final class NexusRecoveryController {
    private(set) var attempts: [UUID: Int] = [:]
    let policy: NexusRetryPolicy

    init(policy: NexusRetryPolicy = NexusRetryPolicy()) { self.policy = policy }

    func nextAttempt(for callID: UUID) -> Int? {
        let next = (attempts[callID] ?? 0) + 1
        guard next <= policy.maxAttempts else { return nil }
        attempts[callID] = next
        return next
    }

    func reset() { attempts.removeAll() }
}
