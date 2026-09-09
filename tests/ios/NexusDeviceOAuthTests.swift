import XCTest
import Security
@testable import BlackGod

private final class DeviceInferenceProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.kimi.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.requests.append(request) }
        let body = request.url?.path.hasSuffix("/models") == true ? "{\"data\":[{\"id\":\"fixture-model\"}]}" : "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"OK\"},\"finish_reason\":\"stop\"}]}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class DeviceAuthProtocol: URLProtocol {
    static let lock = NSLock()
    static var status = 200
    static var body = "{}"
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "auth.kimi.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.lock.withLock { (Self.status, Self.body) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class NexusDeviceOAuthTests: XCTestCase {
    private let proof = NexusOAuthAttempt(verifier: "fixture-verifier+with/slash", state: "fixture-state")
    private func authorization(_ provider: NexusDeviceProvider, now: Date = Date()) -> [String: Any] {
        var body: [String: Any] = ["user_code": "ABCD-1234", "verification_uri": provider.authBase + "/activate", "interval": 5, "device_code": "private-code", "expires_in": 600]
        if provider.isMiniMax { body["state"] = proof.state; body["expired_in"] = now.addingTimeInterval(600).timeIntervalSince1970 * 1000; body["interval"] = 3000 }
        return body
    }
    private func tokenBody(_ provider: NexusDeviceProvider, now: Date = Date()) -> [String: Any] {
        var body: [String: Any] = ["access_token": "access-fixture", "refresh_token": "refresh+fixture", "expires_in": 3600, "token_type": "Bearer"]
        if provider.isMiniMax { body["expired_in"] = now.addingTimeInterval(3600).timeIntervalSince1970 * 1000; body["status"] = "success" }
        return body
    }
    private func token(_ provider: NexusDeviceProvider = .kimi, session: String = "session-A", access: String = "access-old", seconds: Double = 60) -> NexusOAuthCredential {
        .init(provider: provider, sessionID: session, accessToken: access, refreshToken: "refresh-old", expiresAt: Date().addingTimeInterval(seconds))
    }
    private func fields(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: String(decoding: request.httpBody!, as: UTF8.self).split(separator: "&").map { part in
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(pair[0]).removingPercentEncoding!, String(pair[1]).removingPercentEncoding!)
        })
    }
    @MainActor
    private func withStore(_ body: (NexusKeychain) async throws -> Void) async throws {
        let service = "blackgod.device.tests." + UUID().uuidString
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
        try await body(NexusKeychain(service: service))
    }
    private func chosen(_ entry: NexusModelEntry) -> NexusModelEntry {
        .init(providerID: entry.providerID, providerType: entry.providerType, providerURL: entry.providerURL, modelID: "fixture-model", displayName: entry.displayName, isHidden: false, connectionID: entry.connectionID, oauthSessionID: entry.oauthSessionID)
    }
    func testDeviceHTTPTransportBoundsRejectsRedirectsAndSanitizesMalformedBodies() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DeviceAuthProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let request = NexusDeviceOAuth.request(NexusDeviceProvider.kimi.tokenURL, ["client_id": "fixture"])
        DeviceAuthProtocol.lock.withLock { DeviceAuthProtocol.status = 400; DeviceAuthProtocol.body = "{\"error\":\"authorization_pending\"}" }
        let valid = try await NexusDeviceOAuth.sendHTTP(request, session: session)
        XCTAssertEqual(valid.status, 400); XCTAssertEqual(valid.body["error"] as? String, "authorization_pending")
        for (status, body) in [(307, "{}"), (200, "[]"), (200, "SENSITIVE_BODY"), (200, "{\"secret\":\"" + String(repeating: "x", count: 33000) + "\"}")] {
            DeviceAuthProtocol.lock.withLock { DeviceAuthProtocol.status = status; DeviceAuthProtocol.body = body }
            do { _ = try await NexusDeviceOAuth.sendHTTP(request, session: session); XCTFail("Expected rejection") }
            catch { XCTAssertFalse(error.localizedDescription.contains("SENSITIVE_BODY")) }
        }
    }
    func testDeviceRequestsUseProviderSpecificScopesAndPKCE() async throws {
        for provider in NexusDeviceProvider.allCases {
            var observed: URLRequest?
            let auth = authorization(provider)
            let flow = NexusDeviceOAuth { request in observed = request; return .init(status: 200, body: auth) }
            _ = try await flow.begin(provider, proof: proof)
            let request = try XCTUnwrap(observed), values = fields(request)
            XCTAssertEqual(request.url, provider.deviceURL); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "BlackGod/1.0")
            XCTAssertEqual(values["client_id"], provider.clientID)
            XCTAssertNil(values["client_secret"]); XCTAssertNil(values["code_verifier"])
            if provider == .kimi { XCTAssertEqual(values.count, 1) }
            if provider == .grok { XCTAssertEqual(values["scope"], "openid profile email offline_access grok-cli:access api:access") }
            if provider.isMiniMax {
                XCTAssertEqual(values["scope"], "openid profile coding_plan")
                XCTAssertEqual(values["code_challenge"], proof.challenge); XCTAssertEqual(values["state"], proof.state)
            }
        }
    }
    func testFormEncodingPreservesPlusAmpersandUnicodeAndEquals() {
        let request = NexusDeviceOAuth.request(URL(string: "https://auth.kimi.com")!, ["refresh_token": "a+b/c=d&中"])
        XCTAssertEqual(fields(request)["refresh_token"], "a+b/c=d&中")
        XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("+"))
    }
    func testMiniMaxAbsoluteMillisecondsAndStandardRelativeSeconds() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for provider in NexusDeviceProvider.allCases {
            let auth = try NexusDeviceOAuth.authorization(authorization(provider, now: now), provider: provider, proof: proof, now: now)
            XCTAssertEqual(auth.lifetime, 600, accuracy: 0.01)
            XCTAssertEqual(auth.interval, provider.isMiniMax ? 3 : 5)
            XCTAssertEqual(auth.code, provider.isMiniMax ? "ABCD-1234" : "private-code")
            let credential = try NexusDeviceOAuth.credential(tokenBody(provider, now: now), provider: provider, sessionID: "A", now: now)
            XCTAssertEqual(credential.expiresAt.timeIntervalSince(now), 3600, accuracy: 0.01)
        }
    }
    func testRejectsCrossRegionBrowserURLsAndEmbeddedCredentials() {
        for provider in NexusDeviceProvider.allCases {
            for url in ["https://evil.invalid/activate", provider.authBase + ".evil.invalid/", provider.authBase.replacingOccurrences(of: "https", with: "http"), provider.authBase + ":444/", provider.authBase + "/#fragment", provider.authBase.replacingOccurrences(of: "https://", with: "https://user:pass@")] {
                XCTAssertThrowsError(try provider.validateBrowserURL(url))
            }
        }
        XCTAssertThrowsError(try NexusDeviceProvider.minimax.validateBrowserURL(NexusDeviceProvider.minimaxCN.authBase))
    }
    func testRejectsWrongStateMalformedExpiryAndInvalidIntervals() {
        let now = Date()
        var body = authorization(.minimax); body["state"] = "another-login"
        XCTAssertThrowsError(try NexusDeviceOAuth.authorization(body, provider: .minimax, proof: proof, now: now))
        for (key, value) in [("expires_in", true as Any), ("expires_in", -1), ("interval", true), ("interval", 0), ("interval", 301), ("user_code", "code\nheader")] {
            var body = authorization(.kimi); body[key] = value
            XCTAssertThrowsError(try NexusDeviceOAuth.authorization(body, provider: .kimi, proof: proof, now: now))
        }
    }
    func testRejectsMalformedCredentialsAndForeignResourceDestination() {
        for (key, value) in [("access_token", "bad\nheader" as Any), ("refresh_token", "bad secret"), ("expires_in", true), ("expires_in", 0), ("token_type", "Basic"), ("token_type", 123), ("refresh_token", 123), ("resource_url", 123), ("resource_url", "https://evil.invalid/v1")] {
            var body = tokenBody(.kimi); body[key] = value
            XCTAssertThrowsError(try NexusDeviceOAuth.credential(body, provider: .kimi, sessionID: "A"))
        }
    }
    func testPollingHonorsSlowDownAndUsesExactGrantFields() async throws {
        for provider in NexusDeviceProvider.allCases {
            var calls = 0, delays: [Double] = [], observed: URLRequest?
            let flow = NexusDeviceOAuth { request in
                calls += 1; observed = request
                if calls == 1 { return .init(status: 400, body: ["error": "authorization_pending"]) }
                if calls == 2 { return .init(status: 400, body: ["error": "slow_down"]) }
                return .init(status: 200, body: self.tokenBody(provider))
            }
            let auth = try NexusDeviceOAuth.authorization(authorization(provider), provider: provider, proof: proof, now: Date())
            let result = try await flow.poll(provider, auth: auth, proof: proof, sessionID: "session", sleep: { delays.append($0) })
            XCTAssertEqual(result.accessToken, "access-fixture"); XCTAssertEqual(calls, 3)
            XCTAssertEqual(delays, [auth.interval, auth.interval, auth.interval + 5])
            let request = try XCTUnwrap(observed), values = fields(request)
            XCTAssertEqual(request.url, provider.tokenURL)
            XCTAssertEqual(values["grant_type"], "urn:ietf:params:oauth:grant-type:device_code")
            XCTAssertEqual(values[provider.isMiniMax ? "user_code" : "device_code"], auth.code)
            XCTAssertEqual(values["code_verifier"], provider.isMiniMax ? proof.verifier : nil)
        }
    }
    func testPollingDenialAndExpirationNeverReturnCredentials() async throws {
        for error in ["access_denied", "expired_token"] {
            let response = NexusDeviceHTTPResponse(status: 400, body: ["error": error, "access_token": "must-not-use"])
            XCTAssertThrowsError(try NexusDeviceOAuth.pollResult(response, provider: .grok, sessionID: "A"))
        }
        let flow = NexusDeviceOAuth { _ in XCTFail("Expired device must not poll"); throw NexusOAuthError.invalidResponse }
        let auth = NexusDeviceAuthorization(code: "code", userCode: "user", browserURL: URL(string: "https://auth.kimi.com")!, lifetime: 0.01, interval: 2)
        do { _ = try await flow.poll(.kimi, auth: auth, proof: proof, sessionID: "A"); XCTFail() } catch { }
    }
    func testRefreshUsesFixedEndpointAndKeepsUnrotatedRefreshToken() async throws {
        for provider in NexusDeviceProvider.allCases {
            var observed: URLRequest?
            var body = tokenBody(provider); body.removeValue(forKey: "refresh_token")
            let flow = NexusDeviceOAuth { observed = $0; return .init(status: 200, body: body) }
            let fresh = try await flow.refresh(token(provider))
            XCTAssertEqual(fresh.refreshToken, "refresh-old"); XCTAssertEqual(fresh.sessionID, "session-A")
            XCTAssertEqual(observed?.url, provider.tokenURL)
            XCTAssertEqual(fields(observed!), ["client_id": provider.clientID, "grant_type": "refresh_token", "refresh_token": "refresh-old"])
        }
    }
    func testTerminalRefreshErrorsAreSanitizedAndDistinguishedFromOutages() async throws {
        for status in [400, 503] {
            let flow = NexusDeviceOAuth { _ in .init(status: status, body: ["error": "invalid_grant", "error_description": "SENSITIVE_TOKEN"]) }
            do { _ = try await flow.refresh(token()); XCTFail() }
            catch {
                XCTAssertFalse(error.localizedDescription.contains("SENSITIVE_TOKEN"))
                if status == 400 { guard case NexusOAuthError.expired = error else { return XCTFail() } }
                else { guard case NexusOAuthError.http(503) = error else { return XCTFail() } }
            }
        }
    }
    @MainActor
    func testDraftPreservesSelectionAndSeparatesAccounts() async throws {
        try await withStore { store in
            let active = self.chosen(NexusDeviceProvider.grok.entry())
            try store.saveConnection(active, apiKey: "manual-key")
            let a = try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: self.token())
            let b = try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: self.token(session: "B", access: "account-B"))
            XCTAssertEqual(store.selectedConnection, active); XCTAssertEqual(store.oauthCredential(for: a)?.sessionID, "session-A")
            XCTAssertThrowsError(try store.selectConnection(id: a.id))
            try store.disconnectOAuth(a.credentialID)
            XCTAssertNil(store.oauthCredential(for: a)); XCTAssertNil(store.key(for: a.credentialID))
            XCTAssertEqual(store.oauthCredential(for: b)?.accessToken, "account-B")
        }
    }
    @MainActor
    func testRotationCompareAndSwapAndStaleFormCannotOverwriteFreshToken() async throws {
        try await withStore { store in
            let old = self.token(), fresh = self.token(access: "rotated", seconds: 3600)
            let draft = try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: old)
            let selected = self.chosen(draft)
            XCTAssertTrue(try store.replaceOAuth(old, with: fresh, entry: draft))
            try store.saveConnection(selected, apiKey: "access-old")
            XCTAssertEqual(store.key(for: draft.credentialID), "rotated")
            XCTAssertEqual(store.oauthCredential(for: selected), fresh); XCTAssertTrue(store.isOAuth(draft.id))
            try store.invalidateOAuth(old, entry: draft)
            XCTAssertEqual(store.oauthCredential(for: draft), fresh)
            try store.disconnectOAuth(draft.id)
            XCTAssertFalse(try store.replaceOAuth(fresh, with: self.token(access: "late"), entry: draft))
        }
    }
    @MainActor
    func testReloginCannotChangeIdentityOfExistingTaskSnapshot() async throws {
        try await withStore { store in
            let old = self.token()
            let draft = try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: old)
            let entry = self.chosen(draft); try store.saveConnection(entry, apiKey: old.accessToken)
            let new = try store.saveDeviceOAuthDraft(entry, credential: self.token(session: "B", access: "other-account"))
            XCTAssertNil(store.oauthCredential(for: entry)); XCTAssertEqual(store.selectedConnection, new)
            XCTAssertFalse(try store.replaceOAuth(old, with: self.token(access: "late"), entry: entry))
            XCTAssertThrowsError(try store.saveConnection(entry, apiKey: old.accessToken))
            let manager = NexusOAuthCredentials(store: store)
            do { _ = try await manager.resolve(entry, fallback: "other-account"); XCTFail() } catch { }
        }
    }
    @MainActor
    func testDestinationChangesCannotReuseAnOAuthSession() async throws {
        try await withStore { store in
            let entry = try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: self.token())
            let changed = NexusModelEntry(providerID: entry.providerID, providerType: entry.providerType, providerURL: "https://evil.invalid/v1", modelID: "model", displayName: "changed", isHidden: false, connectionID: entry.connectionID, oauthSessionID: entry.oauthSessionID)
            XCTAssertNil(store.oauthCredential(for: changed)); XCTAssertThrowsError(try store.saveConnection(changed, apiKey: "old"))
        }
    }
    @MainActor
    func testConcurrentRequestsShareOneRefresh() async throws {
        try await withStore { store in
            let entry = try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: self.token())
            var rotations = 0
            let manager = NexusOAuthCredentials(store: store) { _ in
                rotations += 1; try await Task.sleep(for: .milliseconds(30))
                return self.token(access: "fresh", seconds: 3600)
            }
            async let first = manager.resolve(entry, fallback: "old")
            async let second = manager.resolve(entry, fallback: "old")
            let values = try await [first, second]
            XCTAssertEqual(values, ["fresh", "fresh"]); XCTAssertEqual(rotations, 1)
            let again = try await manager.resolve(entry, fallback: "old")
            XCTAssertEqual(again, "fresh"); XCTAssertEqual(rotations, 1)
        }
    }
    @MainActor
    func testLogoutDuringRefreshCannotReviveCredential() async throws {
        try await withStore { store in
            let entry = try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: self.token())
            let manager = NexusOAuthCredentials(store: store) { _ in
                try store.disconnectOAuth(entry.id)
                return self.token(access: "late", seconds: 3600)
            }
            do { _ = try await manager.resolve(entry, fallback: "old"); XCTFail() } catch { }
            XCTAssertNil(store.key(for: entry.id)); XCTAssertNil(store.oauthCredential(for: entry))
        }
    }
    @MainActor
    func testRefreshOutagePreservesCredentialsButInvalidGrantDisconnects() async throws {
        try await withStore { store in
            let old = self.token(), entry = try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: old)
            let outage = NexusOAuthCredentials(store: store) { _ in throw NexusOAuthError.http(503) }
            do { _ = try await outage.resolve(entry, fallback: "old"); XCTFail() } catch { }
            XCTAssertEqual(store.oauthCredential(for: entry), old)
            let revoked = NexusOAuthCredentials(store: store) { _ in throw NexusOAuthError.expired }
            do { _ = try await revoked.resolve(entry, fallback: "old"); XCTFail() } catch { }
            XCTAssertNil(store.oauthCredential(for: entry)); XCTAssertNil(store.key(for: entry.id))
        }
    }
    @MainActor
    func testFreshCredentialAndManualKeyDoNotRefresh() async throws {
        try await withStore { store in
            let entry = try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: self.token(seconds: 3600))
            let manager = NexusOAuthCredentials(store: store) { _ in XCTFail("Unexpected refresh"); throw NexusOAuthError.invalidResponse }
            let key = try await manager.resolve(entry, fallback: "stale")
            let manual = try await manager.resolve(NexusDeviceProvider.kimi.entry(), fallback: "manual")
            XCTAssertEqual(key, "access-old"); XCTAssertEqual(manual, "manual")
        }
    }
    @MainActor
    func testAllThreeInferencePathsUseRefreshedCredential() async throws {
        try await withStore { store in
            let entry = self.chosen(try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: self.token()))
            let manager = NexusOAuthCredentials(store: store) { _ in self.token(access: "fresh", seconds: 3600) }
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DeviceInferenceProtocol.self]
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            DeviceInferenceProtocol.lock.withLock { DeviceInferenceProtocol.requests = [] }
            let client = NexusClient(session: session, credentialResolver: { try await manager.resolve($0, fallback: $1) }, consentValidator: { _ in })
            let text = try await client.complete(messages: [.init(role: "user", content: "test")], entry: entry, apiKey: "stale")
            let reply = try await client.nativeTurn(messages: [.text(role: "user", content: "test")], tools: [], entry: entry, apiKey: "stale")
            let models = try await client.fetchModels(entry: entry, apiKey: "stale")
            XCTAssertEqual(text, "OK"); XCTAssertEqual(reply.text, "OK"); XCTAssertEqual(models.first?.id, "fixture-model")
            let requests = DeviceInferenceProtocol.lock.withLock { DeviceInferenceProtocol.requests }
            XCTAssertEqual(requests.count, 3)
            XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" })
        }
    }
    @MainActor
    func testCancellingCallerStopsInferenceEvenIfSharedRefreshCompletes() async throws {
        try await withStore { store in
            let entry = self.chosen(try store.saveDeviceOAuthDraft(NexusDeviceProvider.kimi.entry(), credential: self.token()))
            let manager = NexusOAuthCredentials(store: store) { _ in
                try await Task.sleep(for: .milliseconds(30)); return self.token(access: "fresh", seconds: 3600)
            }
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DeviceInferenceProtocol.self]
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            DeviceInferenceProtocol.lock.withLock { DeviceInferenceProtocol.requests = [] }
            let client = NexusClient(session: session, credentialResolver: { try await manager.resolve($0, fallback: $1) }, consentValidator: { _ in })
            let task = Task { try await client.fetchModels(entry: entry, apiKey: "old") }
            try await Task.sleep(for: .milliseconds(10)); task.cancel()
            do { _ = try await task.value; XCTFail() } catch is CancellationError { } catch { XCTFail("Wrong cancellation") }
            XCTAssertTrue(DeviceInferenceProtocol.lock.withLock { DeviceInferenceProtocol.requests.isEmpty })
        }
    }
    @MainActor
    func testDeviceLoginReturnsAndStoresCredentialAfterBrowserClosed() async throws {
        try await withStore { store in
            let flow = NexusDeviceOAuth { request in
                if request.url == NexusDeviceProvider.kimi.deviceURL { return .init(status: 200, body: self.authorization(.kimi)) }
                return .init(status: 200, body: self.tokenBody(.kimi))
            }
            let login = NexusOAuthLogin(keychain: store, deviceOAuth: flow)
            login.startDevice(.kimi)
            for _ in 0..<100 where login.browser == nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNotNil(login.userCode); XCTAssertNotNil(login.browser)
            login.browserDismissed(); XCTAssertTrue(login.isRunning)
            login.reopenBrowser(); XCTAssertNotNil(login.browser)
            for _ in 0..<600 where login.isRunning { try await Task.sleep(for: .milliseconds(10)) }
            let entry = try XCTUnwrap(login.completedEntry)
            XCTAssertEqual(store.oauthCredential(for: entry)?.accessToken, "access-fixture")
            XCTAssertNil(login.browser); XCTAssertNil(login.userCode); XCTAssertFalse(login.isRunning)
        }
    }
    @MainActor
    func testDeviceLoginCancellationDiscardsLateAuthorization() async throws {
        try await withStore { store in
            let flow = NexusDeviceOAuth { _ in
                try? await Task.sleep(for: .milliseconds(50))
                return .init(status: 200, body: self.authorization(.kimi))
            }
            let login = NexusOAuthLogin(keychain: store, deviceOAuth: flow)
            login.startDevice(.kimi); try await Task.sleep(for: .milliseconds(10)); login.cancel()
            try await Task.sleep(for: .milliseconds(70))
            XCTAssertTrue(store.savedConnections.isEmpty); XCTAssertNil(login.completedEntry)
            XCTAssertNil(login.browser); XCTAssertNil(login.userCode); XCTAssertFalse(login.isRunning)
        }
    }
}
