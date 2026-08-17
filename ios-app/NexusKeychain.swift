//
// NexusKeychain.swift — 神枢 iOS 凭据保险箱
//
// owner token、设备桥接令牌与任何第三方 API key 只放入 Keychain；
// 禁止写入 @AppStorage、UserDefaults、日志、URL query 或 SwiftUI 状态快照。

import Foundation
import Security

enum NexusKeychain {
    enum Key: String {
        case ownerToken = "nexus.owner-token"
        case deviceBridgeToken = "nexus.device-bridge-token"
        case legacyAPIKey = "nexus.legacy-api-key"
    }

    private static let service = "com.blackgod888.nexus"

    static func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for key: Key) throws {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var created = base
            attributes.forEach { created[$0.key] = $0.value }
            let inserted = SecItemAdd(created as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw NexusKeychainError.status(inserted) }
        } else if updated != errSecSuccess {
            throw NexusKeychainError.status(updated)
        }
    }

    static func delete(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NexusKeychainError.status(status) }
    }
}

enum NexusKeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status): return "Keychain 写入失败（\(status)）"
        }
    }
}
