import Foundation
import CoreFoundation

/// Public-client compatibility routes. No client secrets or foreign credential files.
/// Each route pins both authentication and inference destinations.
enum NexusDeviceProvider: String, Codable, CaseIterable, Identifiable {
    case kimi = "kimi-oauth", grok = "grok-oauth", minimax = "minimax-oauth", minimaxCN = "minimax-cn-oauth"
    var id: String { rawValue }
    var name: String {
        switch self { case .kimi: return "Kimi Code"; case .grok: return "xAI / Grok"; case .minimax: return "MiniMax 国际区"; case .minimaxCN: return "MiniMax 中国区" }
    }
    var authorizationName: String { switch self { case .kimi: return "Kimi Code"; case .grok: return "Grok CLI"; case .minimax, .minimaxCN: return "MiniMax CLI" } }
    var clientID: String {
        switch self {
        case .kimi: return "17e5f671-d194-4dfb-9706-5516cb48c098"
        case .grok: return "b1a00492-073a-47ea-816f-4c329264a828"
        case .minimax, .minimaxCN: return "659cf4c1-615c-45f6-a5f6-4bf15eb476e5"
        }
    }
    var isMiniMax: Bool { self == .minimax || self == .minimaxCN }
    var type: NexusProviderType { isMiniMax ? .anthropic : .openAICompatible }
    var authBase: String {
        switch self { case .kimi: return "https://auth.kimi.com"; case .grok: return "https://auth.x.ai"; case .minimax: return "https://account.minimax.io"; case .minimaxCN: return "https://account.minimaxi.com" }
    }
    var baseURL: String {
        switch self { case .kimi: return "https://api.kimi.com/coding/v1"; case .grok: return "https://api.x.ai/v1"; case .minimax: return "https://api.minimax.io/anthropic"; case .minimaxCN: return "https://api.minimaxi.com/anthropic" }
    }
    var deviceURL: URL { URL(string: authBase + (self == .kimi ? "/api/oauth/device_authorization" : "/oauth2/device/code"))! }
    var tokenURL: URL { URL(string: authBase + (self == .kimi ? "/api/oauth/token" : "/oauth2/token"))! }
    var documentation: String {
        switch self {
        case .kimi: return "https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command.html"
        case .grok: return "https://github.com/xai-org/grok-build"
        case .minimax, .minimaxCN: return "https://github.com/MiniMax-AI/cli"
        }
    }
    func entry(id: String = UUID().uuidString) -> NexusModelEntry {
        .init(providerID: rawValue, providerType: type, providerURL: baseURL, modelID: "", displayName: name, isHidden: false, connectionID: id)
    }
    func matches(_ entry: NexusModelEntry) -> Bool {
        entry.providerID == rawValue && entry.providerType == type && entry.providerURL == baseURL && entry.connectionID?.isEmpty == false
    }
    func validateBrowserURL(_ text: String) throws -> URL {
        guard text.utf8.count <= 8192, let p = URLComponents(string: text), p.scheme == "https",
              p.user == nil, p.password == nil, p.port == nil || p.port == 443, p.fragment == nil,
              let host = p.host, let url = p.url else { throw NexusOAuthError.invalidResponse }
        let allowed: Set<String>
        switch self {
        case .kimi: allowed = ["auth.kimi.com", "www.kimi.com", "kimi.com"]
        case .grok: allowed = ["auth.x.ai", "accounts.x.ai"]
        case .minimax: allowed = ["account.minimax.io", "platform.minimax.io"]
        case .minimaxCN: allowed = ["account.minimaxi.com", "platform.minimaxi.com"]
        }
        guard allowed.contains(host) else { throw NexusOAuthError.invalidResponse }
        return url
    }
}

struct NexusOAuthCredential: Codable, Equatable {
    let provider: NexusDeviceProvider
    let sessionID: String
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    func matches(_ entry: NexusModelEntry) -> Bool { provider.matches(entry) && entry.oauthSessionID == sessionID }
    static func validSecret(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 8192 && !value.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
    }
}

struct NexusDeviceAuthorization {
    let code: String
    let userCode: String
    let browserURL: URL
    let lifetime: TimeInterval
    let interval: TimeInterval
}

enum NexusDevicePoll {
    case pending, slowDown, success(NexusOAuthCredential)
}

struct NexusDeviceHTTPResponse {
    let status: Int
    let body: [String: Any]
}

struct NexusDeviceOAuth {
    typealias Send = (URLRequest) async throws -> NexusDeviceHTTPResponse
    let send: Send
    init(send: @escaping Send = Self.sendHTTP) { self.send = send }
    static func form(_ fields: [String: String]) -> Data {
        // URLComponents query encoding leaves '+' literal; form encoding must not.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map { key, value in
            key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").utf8)
    }
    static func request(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BlackGod/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = form(fields); return request
    }
    static func sendHTTP(_ request: URLRequest) async throws -> NexusDeviceHTTPResponse {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        return try await sendHTTP(request, session: session)
    }
    static func sendHTTP(_ request: URLRequest, session: URLSession) async throws -> NexusDeviceHTTPResponse {
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request, delegate: NexusOAuthRedirectGuard())
            guard let http = response as? HTTPURLResponse, !(300..<400).contains(http.statusCode) else { throw NexusOAuthError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 32768 else { throw NexusOAuthError.invalidResponse }
                data.append(byte)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NexusOAuthError.http(http.statusCode) }
            return .init(status: http.statusCode, body: json)
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            if let safe = error as? NexusOAuthError { throw safe }
            throw NexusOAuthError.invalidResponse
        }
    }
    func begin(_ provider: NexusDeviceProvider, proof: NexusOAuthAttempt, now: Date = Date()) async throws -> NexusDeviceAuthorization {
        var fields = ["client_id": provider.clientID]
        if provider == .grok { fields["scope"] = "openid profile email offline_access grok-cli:access api:access" }
        if provider.isMiniMax {
            fields["scope"] = "openid profile coding_plan"
            fields["code_challenge"] = proof.challenge; fields["code_challenge_method"] = "S256"; fields["state"] = proof.state
        }
        let response = try await send(Self.request(provider.deviceURL, fields))
        guard response.status == 200 else { throw NexusOAuthError.http(response.status) }
        return try Self.authorization(response.body, provider: provider, proof: proof, now: now)
    }
    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let result = value.doubleValue; return result.isFinite ? result : nil
    }
    static func authorization(_ body: [String: Any], provider: NexusDeviceProvider, proof: NexusOAuthAttempt, now: Date) throws -> NexusDeviceAuthorization {
        if provider.isMiniMax { guard body["state"] as? String == proof.state else { throw NexusOAuthError.invalidCallback } }
        guard let userCode = body["user_code"] as? String, NexusOAuthCredential.validSecret(userCode), userCode.count <= 128,
              let code = (provider.isMiniMax ? body["user_code"] : body["device_code"]) as? String, NexusOAuthCredential.validSecret(code),
              let rawURL = (body["verification_uri_complete"] ?? body["verification_uri"]) as? String else { throw NexusOAuthError.invalidResponse }
        let lifetime: Double
        if provider.isMiniMax {
            guard let ms = number(body["expired_in"]) else { throw NexusOAuthError.invalidResponse }
            lifetime = ms / 1000 - now.timeIntervalSince1970
        } else { guard let ttl = number(body["expires_in"]) else { throw NexusOAuthError.invalidResponse }; lifetime = ttl }
        if body["interval"] != nil, number(body["interval"]) == nil { throw NexusOAuthError.invalidResponse }
        let interval = provider.isMiniMax ? (number(body["interval"]) ?? 3000) / 1000 : (number(body["interval"]) ?? 5)
        guard lifetime > 0, interval > 0, interval <= 300 else { throw NexusOAuthError.invalidResponse }
        return .init(code: code, userCode: userCode, browserURL: try provider.validateBrowserURL(rawURL), lifetime: min(lifetime, 900), interval: max(interval, 2))
    }
    static func credential(_ body: [String: Any], provider: NexusDeviceProvider, sessionID: String,
                           previousRefresh: String? = nil, now: Date = Date()) throws -> NexusOAuthCredential {
        guard let token = body["access_token"] as? String, NexusOAuthCredential.validSecret(token) else { throw NexusOAuthError.invalidResponse }
        if let rawType = body["token_type"] {
            guard let type = rawType as? String, type.lowercased() == "bearer" else { throw NexusOAuthError.invalidResponse }
        }
        if let rawRefresh = body["refresh_token"], !(rawRefresh is String) { throw NexusOAuthError.invalidResponse }
        if let rawResource = body["resource_url"], !(rawResource is String) { throw NexusOAuthError.invalidResponse }
        let refresh = (body["refresh_token"] as? String) ?? previousRefresh
        if let refresh, !NexusOAuthCredential.validSecret(refresh) { throw NexusOAuthError.invalidResponse }
        let expires: Date
        if provider.isMiniMax {
            guard let ms = number(body["expired_in"]) else { throw NexusOAuthError.invalidResponse }
            expires = Date(timeIntervalSince1970: ms / 1000)
        } else {
            guard let seconds = number(body["expires_in"]), seconds > 0, seconds <= 31_536_000 else { throw NexusOAuthError.invalidResponse }
            expires = now.addingTimeInterval(seconds)
        }
        guard expires > now, expires.timeIntervalSince(now) <= 31_536_000 else { throw NexusOAuthError.invalidResponse }
        // Never follow a provider response to an arbitrary model endpoint.
        if let resource = body["resource_url"] as? String {
            guard let actual = URLComponents(string: resource), let expected = URLComponents(string: provider.baseURL),
                  actual.scheme == "https", actual.host == expected.host, actual.user == nil, actual.password == nil,
                  actual.port == nil || actual.port == 443 else { throw NexusOAuthError.invalidResponse }
        }
        return .init(provider: provider, sessionID: sessionID, accessToken: token, refreshToken: refresh, expiresAt: expires)
    }
    func poll(_ provider: NexusDeviceProvider, auth: NexusDeviceAuthorization, proof: NexusOAuthAttempt, sessionID: String,
              sleep: (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) async throws -> NexusOAuthCredential {
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(auth.lifetime))
        var interval = auth.interval
        while clock.now < deadline {
            try Task.checkCancellation()
            let remaining = clock.now.duration(to: deadline)
            guard remaining >= .seconds(interval) else { throw NexusOAuthError.expired }
            try await sleep(interval); try Task.checkCancellation()
            guard clock.now < deadline else { throw NexusOAuthError.expired }
            var fields = ["client_id": provider.clientID, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"]
            fields[provider.isMiniMax ? "user_code" : "device_code"] = auth.code
            if provider.isMiniMax { fields["code_verifier"] = proof.verifier }
            let response = try await send(Self.request(provider.tokenURL, fields))
            try Task.checkCancellation()
            guard clock.now < deadline else { throw NexusOAuthError.expired }
            switch try Self.pollResult(response, provider: provider, sessionID: sessionID) {
            case .pending: continue
            case .slowDown: interval += 5
            case .success(let token): return token
            }
        }
        throw NexusOAuthError.expired
    }
    static func pollResult(_ response: NexusDeviceHTTPResponse, provider: NexusDeviceProvider, sessionID: String) throws -> NexusDevicePoll {
        let body = response.body
        if provider.isMiniMax, response.status == 200 {
            switch body["status"] as? String {
            case "pending": return .pending
            case "success": return .success(try credential(body, provider: provider, sessionID: sessionID))
            case "error": throw NexusOAuthError.denied
            default: throw NexusOAuthError.invalidResponse
            }
        }
        if response.status == 200, body["error"] == nil { return .success(try credential(body, provider: provider, sessionID: sessionID)) }
        guard response.status == 400 || response.status == 403 else { throw NexusOAuthError.http(response.status) }
        switch body["error"] as? String {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "access_denied": throw NexusOAuthError.denied
        case "expired_token": throw NexusOAuthError.expired
        default: throw NexusOAuthError.http(response.status)
        }
    }
    func refresh(_ old: NexusOAuthCredential) async throws -> NexusOAuthCredential {
        guard let refresh = old.refreshToken else { throw NexusOAuthError.expired }
        let response = try await send(Self.request(old.provider.tokenURL, ["client_id": old.provider.clientID, "grant_type": "refresh_token", "refresh_token": refresh]))
        if ["invalid_grant", "invalid_token", "invalid_refresh_token", "refresh_token_reused"].contains(response.body["error"] as? String ?? ""), (400...403).contains(response.status) { throw NexusOAuthError.expired }
        guard response.status == 200 else { throw NexusOAuthError.http(response.status) }
        if old.provider.isMiniMax { guard response.body["status"] as? String == "success" else { throw NexusOAuthError.invalidResponse } }
        return try Self.credential(response.body, provider: old.provider, sessionID: old.sessionID, previousRefresh: refresh)
    }
}
