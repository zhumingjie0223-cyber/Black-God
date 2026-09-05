import Foundation

/// Black God AI 的任务运行时：协调意图、模型、工具和实时事件。
@MainActor
final class NexusRuntime: ObservableObject {
    @Published private(set) var runState: NexusRunState = .idle
    @Published private(set) var events: [NexusRunEvent] = []

    private(set) var sessionID = UUID()

    func begin(prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        runState = .planning
        append(.planned(prompt: text))
    }

    func append(_ event: NexusRunEvent) {
        events.append(event)
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    func cancel() {
        runState = .cancelled
        append(.status("任务已取消"))
    }

    func reset() {
        sessionID = UUID()
        events.removeAll()
        runState = .idle
    }
}

enum NexusRunState: Equatable {
    case idle, planning, waitingForInput, runningTool(name: String), streaming, paused, completed, failed(String), cancelled
}

enum NexusRunEvent: Identifiable {
    case planned(prompt: String)
    case status(String)
    case text(String)
    case toolStarted(name: String, input: String)
    case toolOutput(String)
    case artifact(name: String, path: String)
    case usage(input: Int, output: Int)
    case completed

    var id: UUID { UUID() }
}

/// 枢语只暴露协议边界；具体词库和引擎可独立替换，不污染 UI。
struct ShuyuIntent {
    let operation: String
    let target: String
    let metadata: [String: String]
}

protocol ShuyuIntentParsing {
    func parse(_ text: String) -> ShuyuIntent
}

struct BasicShuyuParser: ShuyuIntentParsing {
    func parse(_ text: String) -> ShuyuIntent {
        ShuyuIntent(operation: "understand", target: text, metadata: ["protocol": "shuyu"])
    }
}
