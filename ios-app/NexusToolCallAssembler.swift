import Foundation

@MainActor
final class NexusToolCallAssembler {
    private var names: [String: String] = [:]
    private var arguments: [String: String] = [:]

    func append(id: String, name: String?, arguments fragment: String?) -> NexusToolCall? {
        if let name, !name.isEmpty { names[id] = name }
        if let fragment { arguments[id, default: ""] += fragment }
        guard let name = names[id], let raw = arguments[id],
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let uuid = UUID(uuidString: id) else { return nil }
        return NexusToolCall(id: uuid, name: name, arguments: object)
    }

    func reset() { names.removeAll(); arguments.removeAll() }
}
