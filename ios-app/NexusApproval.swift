import Foundation

@MainActor
final class NexusApprovalQueue: ObservableObject {
    @Published private(set) var pending: [NexusToolCall] = []
    private var decisions: [UUID: Bool] = [:]

    func enqueue(_ call: NexusToolCall) {
        guard !pending.contains(where: { $0.id == call.id }) else { return }
        pending.append(call)
    }

    func approve(_ id: UUID) { decide(id, approved: true) }
    func reject(_ id: UUID) { decide(id, approved: false) }

    func decision(for id: UUID) -> Bool? { decisions[id] }

    private func decide(_ id: UUID, approved: Bool) {
        decisions[id] = approved
        pending.removeAll { $0.id == id }
    }
}
