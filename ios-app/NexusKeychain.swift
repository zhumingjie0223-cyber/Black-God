// NexusKeychain.swift — API Key 安全存储

import Foundation
import Security

final class NexusKeychain {
    static let shared = NexusKeychain()
    private init() {}

    private let service = "com.blackgod.nexus"
    private let apiKeyAccount = "anthropic_api_key"
    private let modelAccount = "selected_model"

    func key(for providerID: String) -> String? {
        load(account: "provider_api_key_\(providerID)") ?? (providerID == "anthropic" ? apiKey : nil)
    }

    func setKey(_ value: String?, for providerID: String) {
        let account = "provider_api_key_\(providerID)"
        if let value, !value.isEmpty { save(value, account: account) } else { delete(account: account) }
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
        get { load(account: modelAccount) ?? "claude-opus-5" }
        set { save(newValue, account: modelAccount) }
    }

    var hasAPIKey: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty
    }

    /// 抹掉本 App 在钥匙串里的全部条目（所有服务商 Key + 选中模型）。按 service 整体删，不逐个 account 枚举。
    func wipeAll() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ]
        SecItemDelete(query as CFDictionary)
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
