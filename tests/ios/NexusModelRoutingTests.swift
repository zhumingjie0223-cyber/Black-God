import XCTest
@testable import BlackGod

@MainActor
final class NexusModelRoutingTests: XCTestCase {
    private func entry(id: String, model: String = "fixture-model", base: String = "https://fixture.invalid/v1") -> NexusModelEntry {
        NexusModelEntry(providerID: "fixture", providerType: .openAICompatible,
            providerURL: base, modelID: model, displayName: id, isHidden: false, connectionID: id)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "blackgod.model-routing.tests." + UUID().uuidString
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testDefaultIsLocalAndDoesNotReadAdditionalCredentials() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planning = entry(id: "main"), candidate = entry(id: "intent")
        let consent = NexusDataConsent(defaults: defaults)
        consent.set(true, for: candidate)
        let routing = NexusModelRouting(defaults: defaults, connections: { [planning, candidate] },
            keyProvider: { _ in XCTFail("Local compilation must not read another credential"); return nil }, consent: consent)

        XCTAssertNil(routing.intentConnection(for: planning))
        let snapshot = routing.snapshot(for: planning, apiKey: "main-fixture")
        XCTAssertTrue(snapshot.usesLocalCompiler)
        XCTAssertEqual(snapshot.planning, planning)
        XCTAssertEqual(snapshot.planningAPIKey, "main-fixture")
        XCTAssertNil(snapshot.intentAPIKey)
    }

    func testExplicitAuthorizedConnectionHasOnlyIntentRoleAndPersistsOnlyItsID() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planning = entry(id: "main"), candidate = entry(id: "another-account", base: "https://other.invalid/v1")
        let consent = NexusDataConsent(defaults: defaults)
        consent.set(true, for: candidate)
        let routing = NexusModelRouting(defaults: defaults, connections: { [planning, candidate] },
            keyProvider: { $0 == candidate.credentialID ? "intent-fixture-secret" : nil }, consent: consent)
        routing.intentConnectionID = candidate.id

        let snapshot = routing.snapshot(for: planning, apiKey: "main-fixture-secret")
        XCTAssertEqual(snapshot.planning, planning)
        XCTAssertEqual(snapshot.intent, candidate)
        XCTAssertEqual(snapshot.intentAPIKey, "intent-fixture-secret")
        XCTAssertFalse(snapshot.usesLocalCompiler)
        XCTAssertEqual(NexusModelRouting(defaults: defaults, connections: { [candidate] }, consent: consent).intentConnectionID, candidate.id)
        let stored = defaults.persistentDomain(forName: suite) ?? [:]
        XCTAssertEqual(stored["blackgod.model-routing.intent-connection-id.v1"] as? String, candidate.id)
        XCTAssertFalse(stored.values.contains { String(describing: $0).contains("fixture-secret") })
    }

    func testUnauthorizedRemovedUnknownOrInvalidRoleDoesNotChooseAnotherConnection() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planning = entry(id: "main"), unauthorized = entry(id: "private"), authorized = entry(id: "authorized")
        let invalid = entry(id: "invalid", base: "http://fixture.invalid")
        let empty = entry(id: "empty", model: " ")
        let consent = NexusDataConsent(defaults: defaults)
        [planning, authorized, invalid, empty].forEach { consent.set(true, for: $0) }
        let routing = NexusModelRouting(defaults: defaults, connections: { [planning, unauthorized, authorized, invalid, empty] },
            keyProvider: { _ in XCTFail("Rejected roles must not access credentials"); return nil }, consent: consent)

        XCTAssertEqual(routing.eligibleIntentConnections(for: planning), [authorized])
        for id in [unauthorized.id, invalid.id, empty.id, planning.id, "removed"] {
            routing.intentConnectionID = id
            XCTAssertNil(routing.intentConnection(for: planning))
            XCTAssertTrue(routing.snapshot(for: planning, apiKey: "main-fixture").usesLocalCompiler)
        }
    }

    func testMissingIntentCredentialFallsBackToLocalWithoutChangingPlanning() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planning = entry(id: "main"), candidate = entry(id: "intent")
        let consent = NexusDataConsent(defaults: defaults)
        consent.set(true, for: candidate)
        for key in [nil, "", " \n"] as [String?] {
            let routing = NexusModelRouting(defaults: defaults, connections: { [candidate] },
                keyProvider: { _ in key }, consent: consent)
            routing.intentConnectionID = candidate.id
            let snapshot = routing.snapshot(for: planning, apiKey: "main-fixture")
            XCTAssertTrue(snapshot.usesLocalCompiler)
            XCTAssertEqual(snapshot.planning, planning)
            XCTAssertNil(snapshot.intentAPIKey)
        }
    }

    func testTaskSnapshotFreezesEntriesCredentialsAndRoleWhileConsentRemainsRevocable() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planning = entry(id: "main"), original = entry(id: "intent-A"), replacement = entry(id: "intent-B")
        let consent = NexusDataConsent(defaults: defaults)
        [original, replacement].forEach { consent.set(true, for: $0) }
        var saved = [original, replacement]
        var key = "original-fixture"
        let routing = NexusModelRouting(defaults: defaults, connections: { saved }, keyProvider: { _ in key }, consent: consent)
        routing.intentConnectionID = original.id
        let submitted = routing.snapshot(for: planning, apiKey: "planning-fixture")

        routing.intentConnectionID = replacement.id
        saved = [replacement]
        key = "replacement-fixture"
        let next = routing.snapshot(for: planning, apiKey: "new-planning-fixture")
        XCTAssertEqual(submitted.intent, original)
        XCTAssertEqual(submitted.intentAPIKey, "original-fixture")
        XCTAssertEqual(submitted.planningAPIKey, "planning-fixture")
        XCTAssertEqual(next.intent, replacement)
        XCTAssertEqual(next.intentAPIKey, "replacement-fixture")
        consent.set(false, for: original)
        XCTAssertThrowsError(try consent.require(XCTUnwrap(submitted.intent)))
        consent.set(false, for: replacement)
        XCTAssertNil(routing.intentConnection(for: planning))
        XCTAssertTrue(routing.snapshot(for: planning, apiKey: "planning-fixture").usesLocalCompiler)
    }

    func testConsentDoesNotCarryOverWhenSavedDestinationOrSessionChanges() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planning = entry(id: "main"), approved = entry(id: "intent")
        let consent = NexusDataConsent(defaults: defaults)
        consent.set(true, for: approved)
        var candidate = approved
        let routing = NexusModelRouting(defaults: defaults, connections: { [candidate] },
            keyProvider: { _ in "fixture" }, consent: consent)
        routing.intentConnectionID = approved.id
        XCTAssertNotNil(routing.intentConnection(for: planning))

        candidate = entry(id: approved.id, base: "https://changed.invalid/v1")
        XCTAssertNil(routing.intentConnection(for: planning))
        candidate = approved
        candidate.oauthSessionID = "new-session"
        XCTAssertNil(routing.intentConnection(for: planning))
        routing.intentConnectionID = ""
        XCTAssertNil(defaults.string(forKey: "blackgod.model-routing.intent-connection-id.v1"))
    }
}
