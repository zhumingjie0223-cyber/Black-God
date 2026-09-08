import Foundation

/// All calls for one login share one rotation. Tasks retain their original login
/// session ID, so switching accounts never silently changes a running task's identity.
@MainActor
final class NexusOAuthCredentials {
    static let shared = NexusOAuthCredentials()
    private let store: NexusKeychain
    private let refresh: (NexusOAuthCredential) async throws -> NexusOAuthCredential
    private var flights: [String: (id: UUID, task: Task<String, Error>)] = [:]
    init(store: NexusKeychain = .shared,
         refresh: @escaping (NexusOAuthCredential) async throws -> NexusOAuthCredential = { try await NexusDeviceOAuth().refresh($0) }) {
        self.store = store; self.refresh = refresh
    }
    func resolve(_ entry: NexusModelEntry, fallback: String) async throws -> String {
        try Task.checkCancellation()
        guard entry.oauthSessionID != nil else { return fallback }
        guard let old = store.oauthCredential(for: entry) else { throw NexusOAuthError.expired }
        if old.expiresAt.timeIntervalSinceNow > 120 { return old.accessToken }
        let key = entry.credentialID + "/" + old.sessionID
        let flight: (id: UUID, task: Task<String, Error>)
        if let active = flights[key] { flight = active }
        else {
            let id = UUID()
            let task = Task { [store, refresh] in
                do {
                    let fresh = try await refresh(old)
                    guard try store.replaceOAuth(old, with: fresh, entry: entry) else { throw NexusOAuthError.expired }
                    return fresh.accessToken
                } catch {
                    if case NexusOAuthError.expired = error { try? store.invalidateOAuth(old, entry: entry) }
                    if let safe = error as? NexusOAuthError { throw safe }
                    if error is CancellationError { throw error }
                    // Never expose a provider body or transport error containing credentials.
                    throw NexusOAuthError.invalidResponse
                }
            }
            flight = (id, task); flights[key] = flight
        }
        defer { if flights[key]?.id == flight.id { flights.removeValue(forKey: key) } }
        let token = try await flight.task.value
        try Task.checkCancellation()
        guard store.oauthCredential(for: entry)?.accessToken == token else { throw NexusOAuthError.expired }
        return token
    }
}
