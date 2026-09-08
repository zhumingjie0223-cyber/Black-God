import Foundation

struct NexusRemoteModel: Identifiable, Equatable {
    let id: String
    let name: String
}

enum NexusModelsAPI {
    static func endpoint(_ entry: NexusModelEntry) -> URL? {
        guard let url = NexusEndpoint.url(base: entry.providerURL, type: entry.providerType),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var path = parts.path
        if entry.providerType != .gemini {
            for suffix in ["/chat/completions", "/responses", "/messages"] where path.hasSuffix(suffix) {
                path.removeLast(suffix.count)
            }
        }
        parts.path = path + "/models"
        return parts.url
    }
    static func decode(_ data: Data, type: NexusProviderType) throws -> [NexusRemoteModel] {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = body[type == .gemini ? "models" : "data"] as? [[String: Any]] else { throw NexusError.invalidResponse }
        var seen = Set<String>()
        return list.prefix(2000).compactMap { item in
            if type == .gemini, let methods = item["supportedGenerationMethods"] as? [String], !methods.contains("generateContent") { return nil }
            guard let raw = item[type == .gemini ? "name" : "id"] as? String else { return nil }
            let id = type == .gemini && raw.hasPrefix("models/") ? String(raw.dropFirst(7)) : raw
            guard !id.isEmpty, id.count <= 200, seen.insert(id).inserted else { return nil }
            return NexusRemoteModel(id: id, name: item["displayName"] as? String ?? item["display_name"] as? String ?? id)
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}
