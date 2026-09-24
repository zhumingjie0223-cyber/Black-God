import XCTest
import Security
import Combine
@testable import BlackGod

private final class OAuthFixtureProtocol: URLProtocol {
    static let lock = NSLock()
    static var responseStatus = 200
    static var body = ""
    static var observed: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "openrouter.ai" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.lock.withLock { Self.observed = request; return (Self.responseStatus, Data(Self.body.utf8)) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class NexusOAuthTests: XCTestCase {
    private let attempt = NexusOAuthAttempt(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "test-state")
    private func entry(model: String = "", id: String = UUID().uuidString) -> NexusModelEntry {
        .init(providerID: "openrouter", providerType: .openAICompatible, providerURL: NexusOAuthProvider.openRouterBase,
              modelID: model, displayName: "OAuth fixture", isHidden: false, connectionID: id)
    }
    private func withKeychain(_ body: (NexusKeychain) throws -> Void) rethrows {
        let service = "blackgod.oauth.tests." + UUID().uuidString
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
        try body(NexusKeychain(service: service))
    }
    // 等待真实的浏览器就绪事件，不把冷启动的网络监听器限制在一秒内。
    @MainActor
    private func startLogin(_ login: NexusOAuthLogin, entry: NexusModelEntry,
                            file: StaticString = #filePath, line: UInt = #line) async throws -> NexusOAuthBrowser {
        let ready = expectation(description: "本地回调监听器就绪并生成授权页面")
        let observer = login.$browser.compactMap { $0 }.first().sink { _ in ready.fulfill() }
        defer { observer.cancel() }
        login.start(entry: entry)
        await fulfillment(of: [ready], timeout: 10)
        return try XCTUnwrap(login.browser, "登录初始化未完成：\(login.status)", file: file, line: line)
    }

    func testPKCEAgainstRFC7636VectorAndIndependentRandomSessions() throws {
        XCTAssertEqual(attempt.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let a = try NexusOAuthAttempt(), b = try NexusOAuthAttempt()
        XCTAssertNotEqual(a.verifier, b.verifier); XCTAssertNotEqual(a.state, b.state)
        XCTAssertEqual(a.verifier.count, 43); XCTAssertEqual(a.state.count, 43)
        let parts = URLComponents(url: a.authorizationURL(port: 44111), resolvingAgainstBaseURL: false)!
        XCTAssertEqual(parts.host, "openrouter.ai")
        let callback = parts.queryItems!.first { $0.name == "callback_url" }!.value!
        XCTAssertEqual(callback, a.callbackURL(port: 44111).absoluteString)
        XCTAssertFalse(a.authorizationURL(port: 44111).absoluteString.contains(a.verifier))
    }
    func testCallbackRejectsCrossSessionDuplicateAndAmbiguousParameters() throws {
        let base = attempt.callbackURL(port: 44111).absoluteString
        XCTAssertEqual(try attempt.code(from: URL(string: base + "&code=ok")!, port: 44111), "ok")
        for suffix in ["&code=a&code=b", "&state=other&code=a", "&code=", "&code=a&error=no", "&code=a%0Ab", "&code=a%20b", "&code=a#fragment"] {
            XCTAssertThrowsError(try attempt.code(from: URL(string: base + suffix)!, port: 44111))
        }
        XCTAssertThrowsError(try attempt.code(from: URL(string: base.replacingOccurrences(of: "test-state", with: "other") + "&code=a")!, port: 44111))
        XCTAssertThrowsError(try attempt.code(from: URL(string: base + "&error=access_denied")!, port: 44111)) { error in
            guard case NexusOAuthError.denied = error else { return XCTFail("Expected denial") }
        }
    }
    func testCallbackRequiresExactAuthorityPortAndPath() {
        for url in ["https://localhost:44111/oauth/openrouter/callback?state=test-state&code=a", "http://evil.invalid:44111/oauth/openrouter/callback?state=test-state&code=a", "http://localhost:44112/oauth/openrouter/callback?state=test-state&code=a", "http://user@localhost:44111/oauth/openrouter/callback?state=test-state&code=a", "http://localhost:44111/oauth/openrouter/%63allback?state=test-state&code=a"] {
            XCTAssertThrowsError(try attempt.code(from: URL(string: url)!, port: 44111))
        }
    }
    func testHTTPReceiverRejectsForeignHostsAndUnexpectedMethods() throws {
        let good = "GET /oauth/openrouter/callback?state=test-state&code=a HTTP/1.1\r\nHost: localhost:44111\r\n\r\n"
        let url = try NexusOAuthCallback.callbackURL(request: Data(good.utf8), port: 44111)
        XCTAssertEqual(try attempt.code(from: url, port: 44111), "a")
        for request in [good.replacingOccurrences(of: "GET", with: "POST"), good.replacingOccurrences(of: "localhost", with: "evil.invalid"), good.replacingOccurrences(of: "Host:", with: "Host: localhost:44111\r\nHost:"), good.replacingOccurrences(of: "GET /", with: "GET //"), String(repeating: "a", count: 9000)] {
            XCTAssertThrowsError(try NexusOAuthCallback.callbackURL(request: Data(request.utf8), port: 44111))
        }
    }
    func testExchangeOnlySendsCodeAndProofToFixedHTTPSDestination() throws {
        let request = try attempt.exchangeRequest(code: "one-time-code")
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/auth/keys")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
        XCTAssertEqual(body, ["code": "one-time-code", "code_verifier": attempt.verifier, "code_challenge_method": "S256"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
    func testExchangeValidatesResponseAndNeverEchoesProviderSecrets() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OAuthFixtureProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let exchange = NexusOAuthExchange(session: session)
        OAuthFixtureProtocol.lock.withLock { OAuthFixtureProtocol.responseStatus = 200; OAuthFixtureProtocol.body = "{\"key\":\"fixture-secret\"}" }
        let key = try await exchange.exchange(attempt, code: "test-code"); XCTAssertEqual(key, "fixture-secret")
        for (status, body) in [(403, "SENSITIVE_PROVIDER_BODY"), (200, "{\"key\":\"bad\\nkey\"}"), (200, "{\"key\":\"\"}"), (200, String(repeating: "SENSITIVE_PROVIDER_BODY", count: 1200)), (200, "not-json")] {
            OAuthFixtureProtocol.lock.withLock { OAuthFixtureProtocol.responseStatus = status; OAuthFixtureProtocol.body = body }
            do { _ = try await exchange.exchange(attempt, code: "test-code"); XCTFail("Expected failure") }
            catch { XCTAssertFalse(error.localizedDescription.contains("SENSITIVE_PROVIDER_BODY")); XCTAssertFalse(error.localizedDescription.contains("test-code")) }
        }
    }
    func testRedirectIsRejectedRatherThanResendingProof() {
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        let response = HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 307, httpVersion: nil, headerFields: ["Location": "https://evil.invalid/"])!
        NexusOAuthRedirectGuard().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://evil.invalid/")!)) { redirected in XCTAssertNil(redirected) }
    }
    func testDraftPersistsWithoutSelectingUnknownModelAndDisconnectPreservesOtherAccount() throws {
        try withKeychain { store in
            let active = entry(model: "fixture-model")
            try store.saveConnection(active, apiKey: "original-key")
            let draft = entry(); try store.saveOAuthDraft(draft, credential: "oauth-key")
            XCTAssertEqual(store.selectedConnection, active)
            XCTAssertTrue(store.savedConnections.contains(draft)); XCTAssertTrue(store.isOAuth(draft.credentialID))
            XCTAssertThrowsError(try store.selectConnection(id: draft.id))
            XCTAssertEqual(store.key(for: draft.credentialID), "oauth-key")
            let selected = entry(model: "chosen-model", id: draft.credentialID)
            try store.saveConnection(selected, apiKey: "oauth-key")
            XCTAssertTrue(store.isOAuth(selected.credentialID)); XCTAssertEqual(store.selectedConnection, selected)
            try store.disconnectOAuth(selected.credentialID)
            XCTAssertNil(store.key(for: selected.credentialID)); XCTAssertFalse(store.isOAuth(selected.credentialID))
            XCTAssertEqual(store.key(for: active.credentialID), "original-key")
        }
    }
    func testFirstOAuthDraftSurvivesReloadAndCannotStoreAgainstCustomEndpoint() throws {
        try withKeychain { store in
            let draft = entry(); try store.saveOAuthDraft(draft, credential: "fixture")
            XCTAssertNil(store.selectedConnection); XCTAssertEqual(store.savedConnections, [draft])
            let custom = NexusModelEntry(providerID: "openrouter", providerType: .openAICompatible, providerURL: "https://evil.invalid/v1", modelID: "", displayName: "fake", isHidden: false, connectionID: draft.connectionID)
            XCTAssertThrowsError(try store.saveOAuthDraft(custom, credential: "new-key"))
            XCTAssertEqual(store.key(for: draft.credentialID), "fixture")
            XCTAssertThrowsError(try store.saveOAuthDraft(draft, credential: "bad\nkey"))
        }
    }
    @MainActor
    func testRealLoopbackIgnoresBadCallbackThenReceivesGoodCodeOnce() async throws {
        let server = NexusOAuthCallback(attempt: attempt); defer { server.cancel() }
        let port = try await server.start(timeoutSeconds: 5)
        let base = attempt.callbackURL(port: port).absoluteString
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let (_, bad) = try await session.data(from: URL(string: base + "&code=a&state=other")!)
        XCTAssertEqual((bad as? HTTPURLResponse)?.statusCode, 400)
        let (_, good) = try await session.data(from: URL(string: base + "&code=fixture-code")!)
        XCTAssertEqual((good as? HTTPURLResponse)?.statusCode, 200)
        let code = try await server.waitForCode(); XCTAssertEqual(code, "fixture-code")
        // Listener is one-shot and closed after success.
        do { _ = try await session.data(from: URL(string: base + "&code=second")!); XCTFail("Receiver should close") } catch {}
    }
    @MainActor
    func testReceiverTimeoutAndCancellationReleaseWaiters() async throws {
        let expired = NexusOAuthCallback(attempt: attempt)
        _ = try await expired.start(timeoutSeconds: 0.05)
        do { _ = try await expired.waitForCode(); XCTFail("Expected timeout") }
        catch { guard case NexusOAuthError.expired = error else { return XCTFail("Wrong error") } }
        let cancelled = NexusOAuthCallback(attempt: attempt)
        _ = try await cancelled.start(); let waiting = Task { try await cancelled.waitForCode() }
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        cancelled.cancel()
    }
    @MainActor
    func testFullLoginReceivesCallbackSavesDraftAndClosesBrowser() async throws {
        let service = "blackgod.oauth.tests." + UUID().uuidString
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
        let store = NexusKeychain(service: service), draft = entry()
        let login = NexusOAuthLogin(keychain: store, exchange: { _, code in
            XCTAssertEqual(code, "fixture-code"); return "fixture-key"
        })
        defer { login.cancel() }
        let browser = try await startLogin(login, entry: draft)
        let parts = URLComponents(url: browser.url, resolvingAgainstBaseURL: false)!
        let callback = try XCTUnwrap(parts.queryItems!.first { $0.name == "callback_url" }?.value)
        let finished = expectation(description: "授权完成并退出运行状态")
        let observer = login.$isRunning.filter { !$0 }.first().sink { _ in finished.fulfill() }
        defer { observer.cancel() }
        _ = try await URLSession.shared.data(from: URL(string: callback + "&code=fixture-code")!)
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertFalse(login.isRunning); XCTAssertNil(login.browser); XCTAssertEqual(login.completedEntry, draft)
        XCTAssertEqual(store.key(for: draft.credentialID), "fixture-key"); XCTAssertNil(store.selectedConnection)
    }
    @MainActor
    func testCancelDuringExchangeCannotPersistLateCredential() async throws {
        let service = "blackgod.oauth.tests." + UUID().uuidString
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
        let store = NexusKeychain(service: service), draft = entry()
        let enteredExchange = expectation(description: "授权交换已经开始")
        let returnedExchange = expectation(description: "取消后的迟到结果已经返回")
        var release: CheckedContinuation<String, Never>?
        let login = NexusOAuthLogin(keychain: store, exchange: { _, _ in
            enteredExchange.fulfill()
            let key = await withCheckedContinuation { release = $0 }
            returnedExchange.fulfill()
            return key
        })
        defer { release?.resume(returning: "cleanup"); release = nil }
        defer { login.cancel() }
        let browser = try await startLogin(login, entry: draft)
        let callback = URLComponents(url: browser.url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "callback_url" }!.value!
        _ = try await URLSession.shared.data(from: URL(string: callback + "&code=fixture")!)
        await fulfillment(of: [enteredExchange], timeout: 10)
        login.cancel(); release?.resume(returning: "late-key"); release = nil
        await fulfillment(of: [returnedExchange], timeout: 10)
        XCTAssertNil(store.key(for: draft.credentialID)); XCTAssertNil(login.completedEntry)
        XCTAssertFalse(login.isRunning)
    }
}
