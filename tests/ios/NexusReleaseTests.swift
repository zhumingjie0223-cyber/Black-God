import XCTest
@testable import BlackGod

final class NexusReleaseTests: XCTestCase {
    private func entry(base: String = "https://api.anthropic.com", id: String = "account-A", session: String? = nil, workspace: String? = nil) -> NexusModelEntry {
        .init(providerID: "anthropic", providerType: .anthropic, providerURL: base, modelID: "fixture-model", displayName: "Claude", isHidden: false, connectionID: id, oauthSessionID: session, anthropicWorkspaceID: workspace)
    }
    func testPermissionDefaultsOffPersistsAndCanBeRevoked() throws {
        let suite = "blackgod.consent.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
        let consent = NexusDataConsent(defaults: defaults), model = entry()
        XCTAssertThrowsError(try consent.require(model))
        consent.set(true, for: model)
        XCTAssertTrue(NexusDataConsent(defaults: defaults).allows(model))
        XCTAssertNoThrow(try consent.require(model))
        consent.set(false, for: model); XCTAssertThrowsError(try consent.require(model))
    }
    func testPermissionDoesNotTransferToOtherDestinationAccountSessionOrWorkspace() {
        let suite = "blackgod.consent.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
        let consent = NexusDataConsent(defaults: defaults)
        consent.set(true, for: entry())
        for other in [entry(base: "https://evil.invalid"), entry(id: "B"), entry(session: "another-login"), entry(workspace: "wrkspc_B")] {
            XCTAssertFalse(consent.allows(other))
        }
    }
    func testNoConsentStopsChatAndToolsBeforeCredentialRefreshOrNetwork() async throws {
        let suite = "blackgod.consent.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
        let consent = NexusDataConsent(defaults: defaults)
        let client = NexusClient(credentialResolver: { _, _ in XCTFail("Must not access credentials without permission"); return "fixture" }, consentValidator: { try consent.require($0) })
        do { _ = try await client.complete(messages: [.init(role: "user", content: "private")], entry: entry(), apiKey: "fixture"); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("尚未允许")) }
        do { _ = try await client.nativeTurn(messages: [.text(role: "user", content: "private")], tools: [], entry: entry(), apiKey: "fixture"); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("尚未允许")) }
    }
    func testClaudeWorkspaceHeaderAndMalformedHeaderRejection() throws {
        let model = entry(workspace: "wrkspc_fixture123")
        let request = try NexusProviderRequestBuilder.request(model: model, messages: [.init(role: "user", content: "test")], apiKey: "fixture")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-workspace-id"), "wrkspc_fixture123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "fixture")
        XCTAssertNil(AnthropicProviderAdapter().headers(for: entry(), apiKey: "fixture")["anthropic-workspace-id"])
        for invalid in ["not-a-workspace", "wrkspc_x\nInjected:yes", "wrkspc_" + String(repeating: "x", count: 130)] {
            XCTAssertThrowsError(try NexusProviderRequestBuilder.request(model: entry(workspace: invalid), messages: [.init(role: "user", content: "test")], apiKey: "fixture"))
        }
    }
    func testShippingPrivacyResourcesExistAndDeclareRequiredAPIs() throws {
        let policy = try XCTUnwrap(Bundle.main.url(forResource: "PRIVACY_POLICY", withExtension: "md"))
        XCTAssertTrue(try String(contentsOf: policy, encoding: .utf8).contains("OAuth"))
        let manifest = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let body = try PropertyListSerialization.propertyList(from: Data(contentsOf: manifest), format: nil) as! [String: Any]
        XCTAssertEqual(body["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((body["NSPrivacyAccessedAPITypes"] as? [[String: Any]])?.count, 4)
    }
}
