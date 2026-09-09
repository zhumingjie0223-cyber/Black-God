import Foundation
import Combine

/// A bounded view of observable execution, never a model's private reasoning.
@MainActor
final class NexusLiveExecution: ObservableObject {
    enum State: String { case idle, running, answered, warning, failed, cancelled }
    enum Kind { case phase, command, output, error, result }
    struct Entry: Identifiable {
        let id = UUID()
        let time = Date()
        let kind: Kind
        let text: String
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var status = ""
    @Published private(set) var goal = ""
    @Published private(set) var omitted = false
    private var key: String?
    private var seen = Set<UUID>()
    var visible: Bool { state != .idle }

    func begin(goal: String, redacting key: String? = nil) {
        self.key = key
        self.goal = clean(goal, limit: 200)
        entries = []; seen = []; omitted = false
        state = .running; status = "正在理解任务"
    }
    func phase(_ text: String) {
        guard state == .running else { return }
        status = clean(text, limit: 180)
        append(.phase, text)
    }
    func append(_ kind: Kind, _ text: String) {
        guard state == .running else { return }
        entries.append(Entry(kind: kind, text: clean(text, limit: 1200)))
        while entries.count > 60 || entries.reduce(0, { $0 + $1.text.count }) > 16000 {
            entries.removeFirst(); omitted = true
        }
    }
    func observe(_ traces: [NexusToolTrace]) {
        for trace in traces where seen.insert(trace.call.id).inserted {
            append(trace.succeeded ? .result : .error, "\(trace.call.name) · \(trace.succeeded ? "执行成功" : "执行失败")\n\(trace.result)")
        }
    }
    func finish(_ state: State, message: String) {
        guard self.state == .running else { return }
        append(state == .failed ? .error : .phase, message)
        status = clean(message, limit: 180)
        self.state = state
        key = nil
    }
    private func clean(_ text: String, limit: Int) -> String {
        let value = key.flatMap { $0.isEmpty ? nil : $0 }.map { text.replacingOccurrences(of: $0, with: "[凭据已隐藏]") } ?? text
        return NexusEvidence.preview(value, limit: limit)
    }
}
