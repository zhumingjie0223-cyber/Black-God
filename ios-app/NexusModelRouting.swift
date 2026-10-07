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

/// A role preference names an already saved connection; it never supplies a new
/// model, endpoint, credential or permission. The active chat connection remains
/// the planning/execution/final-response connection.
@MainActor
final class NexusModelRouting: ObservableObject {
    static let shared = NexusModelRouting()
    private static let intentRoleKey = "blackgod.model-routing.intent-connection-id.v1"

    private let defaults: UserDefaults
    private let connections: () -> [NexusModelEntry]
    private let keyProvider: (String) -> String?
    private let consent: NexusDataConsent

    @Published var intentConnectionID: String {
        didSet {
            if intentConnectionID.isEmpty { defaults.removeObject(forKey: Self.intentRoleKey) }
            else { defaults.set(intentConnectionID, forKey: Self.intentRoleKey) }
        }
    }

    init(defaults: UserDefaults = .standard,
         connections: @escaping () -> [NexusModelEntry] = { NexusKeychain.shared.savedConnections },
         keyProvider: @escaping (String) -> String? = { NexusKeychain.shared.key(for: $0) },
         consent: NexusDataConsent = .shared) {
        self.defaults = defaults
        self.connections = connections
        self.keyProvider = keyProvider
        self.consent = consent
        intentConnectionID = defaults.string(forKey: Self.intentRoleKey) ?? ""
    }

    /// Only explicit saved, authorized connections can be assigned the intent
    /// role. A name does not establish a model's size, capability or availability.
    func eligibleIntentConnections(for planning: NexusModelEntry) -> [NexusModelEntry] {
        connections().filter {
            $0.id != planning.id && $0.validWorkspace &&
            !$0.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            NexusEndpoint.requestURL(for: $0) != nil && consent.allows($0)
        }
    }

    func intentConnection(for planning: NexusModelEntry) -> NexusModelEntry? {
        guard !intentConnectionID.isEmpty else { return nil }
        // Do not substitute the main model or an unrelated account if this role
        // is absent, revoked, removed, or no longer valid.
        return eligibleIntentConnections(for: planning).first { $0.id == intentConnectionID }
    }

    /// Capture once at task submission. Later role/key/connection changes apply
    /// to the next task. Transport must still check live consent on every request.
    func snapshot(for planning: NexusModelEntry, apiKey: String) -> Snapshot {
        guard let intent = intentConnection(for: planning),
              let key = keyProvider(intent.credentialID),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Snapshot(planning: planning, planningAPIKey: apiKey, intent: nil, intentAPIKey: nil)
        }
        return Snapshot(planning: planning, planningAPIKey: apiKey, intent: intent, intentAPIKey: key)
    }

    struct Snapshot {
        let planning: NexusModelEntry
        let planningAPIKey: String
        let intent: NexusModelEntry?
        let intentAPIKey: String?
        var usesLocalCompiler: Bool { intent == nil }
    }
}
