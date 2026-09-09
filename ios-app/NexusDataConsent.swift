import Foundation
import CryptoKit

/// Permission is explicit, local, versioned and scoped to the destination/account.
/// Saving an API key or completing OAuth does not grant permission to send chats.
struct NexusDataConsent {
    static let shared = NexusDataConsent()
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ entry: NexusModelEntry) -> String {
        let scope = ["v1", entry.credentialID, entry.providerType.rawValue, entry.providerURL,
                     entry.oauthSessionID ?? "", entry.anthropicWorkspaceID ?? ""].joined(separator: "\u{0}")
        return "blackgod.ai-consent." + SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func allows(_ entry: NexusModelEntry) -> Bool { defaults.bool(forKey: key(entry)) }
    func set(_ allowed: Bool, for entry: NexusModelEntry) {
        if allowed { defaults.set(true, forKey: key(entry)) } else { defaults.removeObject(forKey: key(entry)) }
    }
    func require(_ entry: NexusModelEntry) throws {
        guard allows(entry) else { throw NexusError.apiError("尚未允许向此模型服务商发送内容。请在“神枢连接”中查看数据说明并开启发送许可。") }
    }
}
