import Foundation
import Combine

enum NexusProviderType: String, Codable { case anthropic, openAICompatible }

struct NexusModelEntry: Codable, Equatable, Identifiable {
    let providerID: String
    let providerType: NexusProviderType
    let providerURL: String
    let modelID: String
    let displayName: String
    let isHidden: Bool
    var id: String { "\(providerID)/\(modelID)" }
}

protocol NexusProviderAdapter {
    var type: NexusProviderType { get }
    func endpoint(for model: NexusModelEntry) -> URL?
    func headers(for model: NexusModelEntry, apiKey: String) -> [String: String]
}

struct AnthropicProviderAdapter: NexusProviderAdapter {
    let type: NexusProviderType = .anthropic
    func endpoint(for model: NexusModelEntry) -> URL? { URL(string: model.providerURL + "/v1/messages") }
    func headers(for model: NexusModelEntry, apiKey: String) -> [String: String] {
        ["Content-Type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01"]
    }
}

struct OpenAICompatibleProviderAdapter: NexusProviderAdapter {
    let type: NexusProviderType = .openAICompatible
    func endpoint(for model: NexusModelEntry) -> URL? { URL(string: model.providerURL + "/chat/completions") }
    func headers(for model: NexusModelEntry, apiKey: String) -> [String: String] {
        ["Content-Type": "application/json", "Authorization": "Bearer \(apiKey)"]
    }
}

@MainActor
final class NexusModelRegistry: ObservableObject {
    @Published private(set) var models: [NexusModelEntry]
    @Published var selectedID: String

    init() {
        models = NexusModelCatalog.entries
        let saved = NexusKeychain.shared.selectedModel
        selectedID = models.first(where: { $0.modelID == saved })?.id ?? models[0].id
    }

    var selected: NexusModelEntry { models.first(where: { $0.id == selectedID }) ?? models[0] }
    func register(_ model: NexusModelEntry) { if !models.contains(where: { $0.id == model.id }) { models.append(model) } }
    func select(_ id: String) {
        guard let entry = models.first(where: { $0.id == id }) else { return }
        selectedID = id
        NexusKeychain.shared.selectedModel = entry.modelID
    }
}
