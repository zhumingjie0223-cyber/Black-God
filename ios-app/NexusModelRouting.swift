import Foundation
import Combine
import CryptoKit

enum NexusProviderType: String, Codable { case anthropic, openAICompatible, gemini, responses }

struct NexusModelEntry: Codable, Equatable, Identifiable {
    let providerID: String
    let providerType: NexusProviderType
    let providerURL: String
    let modelID: String
    let displayName: String
    let isHidden: Bool
    var nativeToolCalling: Bool? = nil
    var connectionID: String? = nil
    var oauthSessionID: String? = nil
    var anthropicWorkspaceID: String? = nil
    var validWorkspace: Bool {
        guard let id = anthropicWorkspaceID, !id.isEmpty else { return true }
        return providerType == .anthropic && id.hasPrefix("wrkspc_") && id.utf8.count <= 128
            && id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_").contains($0) }
    }
    var credentialID: String { connectionID ?? providerID }
    var usesNativeTools: Bool { nativeToolCalling ?? true }
    var id: String { connectionID ?? "\(providerID)/\(modelID)" }
}

protocol NexusProviderAdapter {
    var type: NexusProviderType { get }
    func endpoint(for model: NexusModelEntry) -> URL?
    func headers(for model: NexusModelEntry, apiKey: String) -> [String: String]
}

struct AnthropicProviderAdapter: NexusProviderAdapter {
    let type: NexusProviderType = .anthropic
    func endpoint(for model: NexusModelEntry) -> URL? { model.validWorkspace ? NexusEndpoint.url(base: model.providerURL, type: .anthropic) : nil }
    func headers(for model: NexusModelEntry, apiKey: String) -> [String: String] {
        var headers = ["Content-Type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01"]
        if model.validWorkspace, let workspace = model.anthropicWorkspaceID, !workspace.isEmpty { headers["anthropic-workspace-id"] = workspace }
        return headers
    }
}

struct OpenAICompatibleProviderAdapter: NexusProviderAdapter {
    let type: NexusProviderType = .openAICompatible
    func endpoint(for model: NexusModelEntry) -> URL? { NexusEndpoint.url(base: model.providerURL, type: .openAICompatible) }
    func headers(for model: NexusModelEntry, apiKey: String) -> [String: String] {
        ["Content-Type": "application/json", "Authorization": "Bearer \(apiKey)"]
    }
}

struct GenericProviderAdapter: NexusProviderAdapter {
    let type: NexusProviderType
    func endpoint(for model: NexusModelEntry) -> URL? { NexusEndpoint.requestURL(for: model) }
    func headers(for model: NexusModelEntry, apiKey: String) -> [String: String] {
        if type == .gemini { return ["Content-Type": "application/json", "x-goog-api-key": apiKey] }
        return ["Content-Type": "application/json", "Authorization": "Bearer " + apiKey]
    }
}

@MainActor
final class NexusModelRegistry: ObservableObject {
    @Published private(set) var models: [NexusModelEntry]
    @Published var selectedID: String

    init() {
        let saved = NexusModelCatalog.entry(for: NexusKeychain.shared.selectedModel)
        var list = NexusModelCatalog.entries
        if !list.contains(where: { $0.id == saved.id }) { list.append(saved) }
        models = list
        selectedID = saved.id
    }

    var selected: NexusModelEntry { models.first(where: { $0.id == selectedID }) ?? models[0] }
    func register(_ model: NexusModelEntry) { if !models.contains(where: { $0.id == model.id }) { models.append(model) } }
    func select(_ id: String) { if models.contains(where: { $0.id == id }) { selectedID = id } }
}

enum NexusEndpoint {
    static func url(base: String, type: NexusProviderType) -> URL? {
        guard var components = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if type == .gemini {
            if path.isEmpty { path = "/v1beta" }
        } else if type == .responses {
            if !path.hasSuffix("/responses") { path += path.isEmpty ? "/v1/responses" : "/responses" }
        } else if type == .anthropic {
            if !path.hasSuffix("/messages") { path += path.hasSuffix("/v1") ? "/messages" : "/v1/messages" }
        } else if !path.hasSuffix("/chat/completions") {
            path += path.isEmpty ? "/v1/chat/completions" : "/chat/completions"
        }
        components.path = path
        return components.url
    }

    static func requestURL(for model: NexusModelEntry) -> URL? {
        guard let base = url(base: model.providerURL, type: model.providerType) else { return nil }
        guard model.providerType == .gemini else { return base }
        let name = model.modelID.hasPrefix("models/") ? String(model.modelID.dropFirst(7)) : model.modelID
        guard !name.isEmpty, name.count <= 200,
              name.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._").contains($0) }) else { return nil }
        return base.appendingPathComponent("models").appendingPathComponent(name + ":generateContent")
    }

    static func credentialID(base: String, type: NexusProviderType) -> String {
        let normalized = url(base: base, type: type)?.absoluteString ?? base
        let digest = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        return "custom_" + digest
    }
}
