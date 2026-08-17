//
// NexusClient.swift — iOS ↔ Cloudflare 神枢协议客户端
//
// 所有对话、Agent plan/approve/execute 与 WebSocket 票据均指向神枢 Worker。
// owner token 从 NexusKeychain 读取；它永不进入 URL、AppStorage 或错误字符串。

import Foundation

struct NexusTalkResponse: Decodable {
    let turnId: String?
    let reply: String
    let model: String?
    let agentSteps: Int?

    enum CodingKeys: String, CodingKey {
        case turnId, reply, model
        case agentSteps = "agent_steps"
    }
}

struct NexusStatsResponse: Decodable {
    let uptimeSeconds: Int?
    let soulVersion: Int?
    let experienceCount: Int?
    let innerVoiceCount: Int?
    let worldEntities: Int?
    let capabilities: Int?
    let storageSizeKB: String?

    enum CodingKeys: String, CodingKey {
        case uptimeSeconds = "uptime_s"
        case soulVersion = "soul_version"
        case experienceCount = "experience_count"
        case innerVoiceCount = "inner_voice_count"
        case worldEntities = "world_entities"
        case capabilities
        case storageSizeKB = "storage_size_est_kb"
    }
}

struct NexusAgentPlanResponse: Decodable {
    let ok: Bool
    let error: String?
    let approvalToken: String?
    let run: NexusAgentRun?
}

struct NexusAgentRun: Decodable, Identifiable {
    let runId: String
    let capability: String
    let phase: String
    let risk: String?
    let approvalRequired: Bool?
    let effectId: String?

    var id: String { runId }
}

enum NexusClientError: LocalizedError {
    case invalidBaseURL
    case ownerTokenMissing
    case badResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "神枢地址无效"
        case .ownerTokenMissing: return "请先在神枢连接设置中保存主人令牌"
        case .badResponse: return "神枢返回无法识别的数据"
        case .server(let status, let message): return "神枢请求失败（\(status)）：\(message)"
        }
    }
}

struct NexusClient {
    let baseURL: URL
    private let session: URLSession

    init(base: String, session: URLSession = .shared) throws {
        let normalized = base.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: normalized), url.scheme == "https" || url.scheme == "http" else {
            throw NexusClientError.invalidBaseURL
        }
        self.baseURL = url
        self.session = session
    }

    private func ownerToken() throws -> String {
        guard let token = NexusKeychain.read(.ownerToken), !token.isEmpty else { throw NexusClientError.ownerTokenMissing }
        return token
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw NexusClientError.invalidBaseURL }
        return url
    }

    private func request(_ path: String, method: String = "POST", body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = method
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try ownerToken())", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NexusClientError.badResponse }
        guard (200...299).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (object?["error"] as? String) ?? "请求未成功"
            throw NexusClientError.server(status: http.statusCode, message: message)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw NexusClientError.badResponse }
    }

    func talk(_ text: String, caps: [String] = ["ios"]) async throws -> NexusTalkResponse {
        let request = try request("/talk", body: ["text": text, "caps": caps])
        return try await decode(NexusTalkResponse.self, request: request)
    }

    func stats() async throws -> NexusStatsResponse {
        var request = URLRequest(url: try endpoint("/stats"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(try ownerToken())", forHTTPHeaderField: "Authorization")
        return try await decode(NexusStatsResponse.self, request: request)
    }

    func plan(capability: String, params: [String: Any], idempotencyKey: String = UUID().uuidString) async throws -> NexusAgentPlanResponse {
        let request = try request("/agent/plan", body: ["capability": capability, "params": params, "idempotencyKey": idempotencyKey])
        return try await decode(NexusAgentPlanResponse.self, request: request)
    }

    func approve(runId: String, approvalToken: String) async throws -> NexusAgentPlanResponse {
        let request = try request("/agent/approve", body: ["runId": runId, "approvalToken": approvalToken])
        return try await decode(NexusAgentPlanResponse.self, request: request)
    }

    func execute(runId: String) async throws -> NexusAgentPlanResponse {
        let request = try request("/agent/execute", body: ["runId": runId])
        return try await decode(NexusAgentPlanResponse.self, request: request)
    }

    /// 仅使用一次性票据建立 WS；owner token 始终只在 HTTPS Authorization header 中传输。
    func webSocketURL() async throws -> URL {
        struct Ticket: Decodable { let ticket: String }
        let request = try request("/wsticket", body: [:])
        let ticket = try await decode(Ticket.self, request: request)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components?.queryItems = [URLQueryItem(name: "t", value: ticket.ticket)]
        guard let url = components?.url else { throw NexusClientError.invalidBaseURL }
        return url
    }
}
