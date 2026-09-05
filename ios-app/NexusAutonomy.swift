import Foundation

struct NexusActionFingerprint: Hashable {
    let name: String
    let arguments: String
}

@MainActor
final class NexusAutonomyController {
    private(set) var completedActions = Set<NexusActionFingerprint>()
    private(set) var failedActions = Set<NexusActionFingerprint>()
    private(set) var replans = 0
    let maxReplans: Int

    init(maxReplans: Int = 3) { self.maxReplans = max(0, maxReplans) }

    func shouldExecute(_ call: NexusToolCall) -> Bool {
        !completedActions.contains(fingerprint(call)) && !failedActions.contains(fingerprint(call))
    }

    func record(_ call: NexusToolCall, succeeded: Bool) {
        let key = fingerprint(call)
        if succeeded { completedActions.insert(key) }
        else { failedActions.insert(key) }
    }

    func canReplan() -> Bool {
        guard replans < maxReplans else { return false }
        replans += 1
        return true
    }

    func reset() {
        completedActions.removeAll()
        failedActions.removeAll()
        replans = 0
    }

    private func fingerprint(_ call: NexusToolCall) -> NexusActionFingerprint {
        NexusActionFingerprint(name: call.name, arguments: call.arguments.keys.sorted().map { "\($0)=\(call.arguments[$0] ?? "")" }.joined(separator: "&"))
    }
}
