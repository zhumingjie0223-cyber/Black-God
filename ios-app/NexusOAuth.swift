import Foundation
import CryptoKit
import Security

/// A provider's OAuth contract is explicit; no arbitrary authorize/token URLs.
enum NexusOAuthProvider {
    static let openRouterBase = "https://openrouter.ai/api/v1"
    static func supports(_ entry: NexusModelEntry) -> Bool {
        entry.providerID == "openrouter" && entry.providerType == .openAICompatible
            && entry.providerURL == openRouterBase && entry.connectionID?.isEmpty == false
    }
}

enum NexusOAuthError: LocalizedError {
    case invalidCallback, denied, expired, unavailable, invalidResponse, http(Int), random
    var errorDescription: String? {
        switch self {
        case .invalidCallback: return "授权返回信息与本次登录不匹配。"
        case .denied: return "本次登录未获授权，可以重新登录。"
        case .expired: return "授权已过期或登录等待超时，请重新登录。"
        case .unavailable: return "无法启动本机授权接收，请重试。"
        case .invalidResponse: return "授权服务未返回有效凭据，请重新登录。"
        case .http(let code): return "授权服务返回 HTTP \(code)，请重试或检查账号。"
        case .random: return "无法生成安全登录会话，请重试。"
        }
    }
}

struct NexusOAuthAttempt {
    let verifier: String
    let state: String
    var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    init(verifier: String, state: String) { self.verifier = verifier; self.state = state }
    init() throws { verifier = try Self.random(); state = try Self.random() }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw NexusOAuthError.random }
        return base64URL(Data(bytes))
    }
    func callbackURL(port: UInt16) -> URL {
        var parts = URLComponents(string: "http://localhost:\(port)/oauth/openrouter/callback")!
        // OpenRouter preserves query parameters inside callback_url.
        parts.queryItems = [URLQueryItem(name: "state", value: state)]
        return parts.url!
    }
    func authorizationURL(port: UInt16) -> URL {
        var parts = URLComponents(string: "https://openrouter.ai/auth")!
        parts.queryItems = [URLQueryItem(name: "callback_url", value: callbackURL(port: port).absoluteString),
            URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "S256")]
        return parts.url!
    }
    func code(from url: URL, port: UInt16) throws -> String {
        guard url.absoluteString.utf8.count <= 8192,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "http", parts.host == "localhost", parts.port == Int(port),
              parts.percentEncodedPath == "/oauth/openrouter/callback", parts.user == nil, parts.password == nil,
              parts.fragment == nil else { throw NexusOAuthError.invalidCallback }
        let items = parts.queryItems ?? []
        func values(_ name: String) -> [String] { items.filter { $0.name == name }.map { $0.value ?? "" } }
        guard values("state") == [state] else { throw NexusOAuthError.invalidCallback }
        let errors = values("error"), codes = values("code")
        if errors.count == 1 && codes.isEmpty { throw NexusOAuthError.denied }
        guard errors.isEmpty, codes.count == 1, let code = codes.first, !code.isEmpty, code.utf8.count <= 4096,
              !code.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }) else { throw NexusOAuthError.invalidCallback }
        return code
    }
    func exchangeRequest(code: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "code_verifier": verifier, "code_challenge_method": "S256"])
        return request
    }
}

final class NexusOAuthRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct NexusOAuthExchange {
    let session: URLSession
    private let ownsSession: Bool
    init(session: URLSession? = nil) {
        ownsSession = session == nil
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.urlCache = nil
            config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: config)
        }
    }
    func exchange(_ attempt: NexusOAuthAttempt, code: String) async throws -> String {
        defer { if ownsSession { session.invalidateAndCancel() } }
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: attempt.exchangeRequest(code: code), delegate: NexusOAuthRedirectGuard())
            guard let http = response as? HTTPURLResponse else { throw NexusOAuthError.invalidResponse }
            guard http.statusCode == 200 else { throw NexusOAuthError.http(http.statusCode) }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 16384 else { throw NexusOAuthError.invalidResponse }
                data.append(byte)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let key = json["key"] as? String, !key.isEmpty, key.utf8.count <= 4096,
                  !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }) else { throw NexusOAuthError.invalidResponse }
            try Task.checkCancellation()
            return key
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            if let safe = error as? NexusOAuthError { throw safe }
            // Do not surface provider bodies or URL errors containing authorization material.
            throw NexusOAuthError.invalidResponse
        }
    }
}
