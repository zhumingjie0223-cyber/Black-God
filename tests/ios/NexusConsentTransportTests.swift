import XCTest
@testable import BlackGod

private actor CredentialRefreshGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private final class ConsentTransportProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var paths: Set<String> = []
    static func wasRequested(_ path: String) -> Bool { lock.withLock { paths.contains(path) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { _ = Self.paths.insert(request.url!.path) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"choices":[{"message":{"content":"should not be sent"},"finish_reason":"stop"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class NexusConsentTransportTests: XCTestCase {
    private func checkRevocation(native: Bool) async throws {
        for type in [NexusProviderType.openAICompatible, .anthropic, .gemini, .responses] {
            let id = UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: id))
            defer { defaults.removePersistentDomain(forName: id) }
            let consent = NexusDataConsent(defaults: defaults)
            let entry = NexusModelEntry(providerID: "fixture", providerType: type, providerURL: "https://fixture.invalid/\(id)/v1",
                modelID: "fixture", displayName: "Fixture", isHidden: false)
            consent.set(true, for: entry)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ConsentTransportProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let gate = CredentialRefreshGate()
            let started = expectation(description: "credential refresh started \(type)")
            let client = NexusClient(session: session, credentialResolver: { _, _ in
                started.fulfill()
                await gate.wait()
                return "fixture"
            }, consentValidator: { try consent.require($0) })
            let task = Task {
                if native {
                    _ = try await client.nativeTurn(messages: [.text(role: "user", content: "private")], tools: [], entry: entry, apiKey: "fixture")
                } else {
                    _ = try await client.complete(messages: [.init(role: "user", content: "private")], entry: entry, apiKey: "fixture")
                }
            }
            await fulfillment(of: [started], timeout: 2)
            // Reproduce Settings revocation while OAuth refresh has suspended the client actor.
            consent.set(false, for: entry)
            await gate.release()
            do {
                try await task.value
                XCTFail("Revoked permission must stop the pending request")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("尚未允许"), error.localizedDescription)
            }
            let endpoint = try XCTUnwrap(NexusProviderRequestBuilder.adapter(for: entry).endpoint(for: entry))
            XCTAssertFalse(ConsentTransportProtocol.wasRequested(endpoint.path), "Private messages must never reach URLSession")
        }
    }

    func testCompleteRechecksConsentAfterCredentialRefresh() async throws {
        try await checkRevocation(native: false)
    }

    func testNativeTurnRechecksConsentAfterCredentialRefresh() async throws {
        try await checkRevocation(native: true)
    }
}
