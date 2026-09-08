// NexusKeychain.swift — API Key 安全存储

import Foundation
import Security

final class NexusKeychain {
    static let shared = NexusKeychain()
    private init() { service = "com.blackgod.nexus" }
    init(service: String) { self.service = service }

    private let lock = NSRecursiveLock()
    private let service: String
    private let apiKeyAccount = "anthropic_api_key"
    private let modelAccount = "selected_model"

    private struct Connections: Codable {
        var selection: NexusModelEntry?
        var keys: [String: String]
        var entries: [String: NexusModelEntry]? = nil
        var oauthIDs: Set<String>? = nil
        var oauthTokens: [String: NexusOAuthCredential]? = nil
    }
    private var connections: Connections? {
        lock.lock(); defer { lock.unlock() }
        guard let text = load(account: "connections_v2") else { return nil }
        return try? JSONDecoder().decode(Connections.self, from: Data(text.utf8))
    }
    private func storeConnections(_ value: Connections) throws {
        try storeChecked(String(decoding: JSONEncoder().encode(value), as: UTF8.self), account: "connections_v2")
    }

    func key(for providerID: String) -> String? {
        if let value = connections?.keys[providerID] { return value.isEmpty ? nil : value }
        return load(account: "provider_api_key_\(providerID)") ?? (providerID == "anthropic" ? apiKey : nil)
    }

    private func storeChecked(_ value: String, account: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: account]
        let status: OSStatus
        if value.isEmpty {
            status = SecItemDelete(query as CFDictionary)
        } else {
            let attributes: [CFString: Any] = [kSecValueData: Data(value.utf8),
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updated == errSecItemNotFound {
                status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            } else { status = updated }
        }
        guard status == errSecSuccess || (value.isEmpty && status == errSecItemNotFound) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "无法保存到本机钥匙串（\(status)）"])
        }
    }

    var selectedConnection: NexusModelEntry? {
        if let saved = connections { return saved.selection }
        guard let text = load(account: "selected_connection"), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NexusModelEntry.self, from: data)
    }

    func saveConnection(_ entry: NexusModelEntry, apiKey: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard entry.validWorkspace, NexusEndpoint.requestURL(for: entry) != nil,
              !entry.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NexusError.apiError("接口地址或模型名称无效。")
        }
        var value = connections ?? Connections(selection: entry, keys: [:])
        // Import only the previously selected legacy provider. Other legacy keys
        // remain readable until their provider is saved into this atomic bundle.
        let storedKey: String
        if entry.oauthSessionID != nil {
            guard let token = value.oauthTokens?[entry.credentialID], token.matches(entry) else { throw NexusOAuthError.expired }
            storedKey = token.accessToken
        } else {
            storedKey = apiKey
            if value.keys[entry.credentialID] != apiKey || value.oauthTokens?[entry.credentialID] != nil {
                value.oauthIDs?.remove(entry.credentialID); value.oauthTokens?.removeValue(forKey: entry.credentialID)
            }
        }
        if let old = selectedConnection, value.keys[old.credentialID] == nil {
            value.keys[old.credentialID] = key(for: old.credentialID) ?? ""
        }
        value.selection = entry
        value.keys[entry.credentialID] = storedKey
        var entries = value.entries ?? [:]
        if let old = selectedConnection { entries[old.id] = old }
        entries[entry.id] = entry
        value.entries = entries
        // One Keychain update commits endpoint, model, switches and credential.
        try storeConnections(value)
    }

    var savedConnections: [NexusModelEntry] {
        guard let value = connections else { return selectedConnection.map { [$0] } ?? [] }
        var entries = value.entries ?? [:]
        if let selected = value.selection { entries[selected.id] = selected }
        return entries.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    func selectConnection(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard var value = connections, let entry = savedConnections.first(where: { $0.id == id }) else { throw NexusError.invalidResponse }
        guard !entry.modelID.isEmpty, !(value.keys[entry.credentialID] ?? "").isEmpty else { throw NexusError.missingAPIKey }
        value.selection = entry
        try storeConnections(value)
    }

    /// OAuth may complete before a model has been chosen. Preserve the active model.
    func saveOAuthDraft(_ entry: NexusModelEntry, credential: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard NexusOAuthProvider.supports(entry), !credential.isEmpty, credential.utf8.count <= 4096,
              !credential.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else { throw NexusOAuthError.invalidResponse }
        var value = connections ?? Connections(selection: selectedConnection, keys: [:])
        if let old = selectedConnection, value.keys[old.credentialID] == nil {
            value.keys[old.credentialID] = key(for: old.credentialID) ?? ""
        }
        var entries = value.entries ?? [:]
        if let old = selectedConnection { entries[old.id] = old }
        entries[entry.id] = entry; value.entries = entries
        value.keys[entry.credentialID] = credential
        var ids = value.oauthIDs ?? []; ids.insert(entry.credentialID); value.oauthIDs = ids
        try storeConnections(value)
    }
    func isOAuth(_ id: String) -> Bool { connections?.oauthIDs?.contains(id) == true }
    func disconnectOAuth(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard var value = connections, value.oauthIDs?.contains(id) == true else { return }
        value.keys[id] = "" // Explicit tombstone prevents falling back to a legacy key.
        value.oauthIDs?.remove(id)
        value.oauthTokens?.removeValue(forKey: id)
        try storeConnections(value)
    }

    func saveDeviceOAuthDraft(_ entry: NexusModelEntry, credential: NexusOAuthCredential) throws -> NexusModelEntry {
        lock.lock(); defer { lock.unlock() }
        guard credential.provider.matches(entry), !credential.sessionID.isEmpty,
              NexusOAuthCredential.validSecret(credential.accessToken),
              credential.refreshToken.map(NexusOAuthCredential.validSecret) ?? true,
              credential.expiresAt > Date() else { throw NexusOAuthError.invalidResponse }
        var entry = entry; entry.oauthSessionID = credential.sessionID
        var value = connections ?? Connections(selection: selectedConnection, keys: [:])
        if let old = selectedConnection, value.keys[old.credentialID] == nil { value.keys[old.credentialID] = key(for: old.credentialID) ?? "" }
        var entries = value.entries ?? [:]
        if let old = selectedConnection { entries[old.id] = old }
        entries[entry.id] = entry; value.entries = entries
        // Reauthorizing the selected connection must also replace its session snapshot.
        if value.selection?.id == entry.id { value.selection = entry }
        value.keys[entry.credentialID] = credential.accessToken
        var tokens = value.oauthTokens ?? [:]; tokens[entry.credentialID] = credential; value.oauthTokens = tokens
        var ids = value.oauthIDs ?? []; ids.insert(entry.credentialID); value.oauthIDs = ids
        try storeConnections(value)
        return entry
    }
    func oauthCredential(for entry: NexusModelEntry) -> NexusOAuthCredential? {
        guard let token = connections?.oauthTokens?[entry.credentialID], token.matches(entry) else { return nil }
        return token
    }
    /// Compare and replace prevents a late refresh from reviving a signed-out account.
    func replaceOAuth(_ old: NexusOAuthCredential, with new: NexusOAuthCredential, entry: NexusModelEntry) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard new.matches(entry), old.matches(entry), NexusOAuthCredential.validSecret(new.accessToken),
              new.refreshToken.map(NexusOAuthCredential.validSecret) ?? true, new.expiresAt > Date() else { throw NexusOAuthError.invalidResponse }
        guard var value = connections, value.oauthTokens?[entry.credentialID] == old else { return false }
        value.oauthTokens?[entry.credentialID] = new; value.keys[entry.credentialID] = new.accessToken
        try storeConnections(value); return true
    }
    func invalidateOAuth(_ old: NexusOAuthCredential, entry: NexusModelEntry) throws {
        lock.lock(); defer { lock.unlock() }
        guard let current = oauthCredential(for: entry), current == old else { return }
        try disconnectOAuth(entry.credentialID)
    }

    // MARK: API Key

    var apiKey: String? {
        get { load(account: apiKeyAccount) }
        set {
            if let value = newValue, !value.isEmpty {
                save(value, account: apiKeyAccount)
            } else {
                delete(account: apiKeyAccount)
            }
        }
    }

    var selectedModel: String {
        connections?.selection?.modelID ?? load(account: modelAccount) ?? "claude-opus-5"
    }

    var hasAPIKey: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty
    }

    // MARK: Keychain 操作

    private func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func load(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
