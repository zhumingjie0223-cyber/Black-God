import Foundation

/// Stable identities keep each app surface's guest files available after restart.
@MainActor
enum NexusWorkspaceIdentity {
    static func id(for name: String, defaults: UserDefaults = .standard) -> UUID {
        let key = "blackgod.workspace." + name
        if let saved = defaults.string(forKey: key), let id = UUID(uuidString: saved) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}
