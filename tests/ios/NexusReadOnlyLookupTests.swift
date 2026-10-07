import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BlackGod

private final class LookupStreamingProtocol: URLProtocol {
    static var onStart: (() -> Void)?
    static var onStop: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if request.url?.path == "/pending" { Self.onStart?(); return }
        if request.url?.path == "/oversize" {
            client?.urlProtocol(self, didLoad: Data(repeating: 120, count: 40))
            client?.urlProtocol(self, didLoad: Data(repeating: 120, count: 40))
        } else { client?.urlProtocol(self, didLoad: Data("public document".utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { if request.url?.path == "/pending" { Self.onStop?() } }
}

final class NexusReadOnlyLookupTests: XCTestCase {
    private let url = URL(string: "https://example.com/report")!
    private func call(_ arguments: [String: String] = ["url": "https://example.com/report"]) -> NexusToolCall {
        NexusToolCall(id: UUID(), name: "web_lookup", arguments: arguments)
    }
    private func tool(_ text: String = "金边报告：本次结果待核验。", mime: String = "text/plain", status: Int = 200) -> NexusReadOnlyLookupTool {
        NexusReadOnlyLookupTool(networkAllowed: { true }, isAuthorizedURL: { $0 == self.url }, transport: { request, _ in
            NexusLookupResponse(data: Data(text.utf8), url: request.url!, statusCode: status, mimeType: mime)
        }, now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    func testDefaultAuthorizationDeniesModelInventedDestination() async {
        let result = await NexusReadOnlyLookupTool(networkAllowed: { true }).execute(call())
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.output.contains("未由用户明确指定"))
    }

    func testQueryStaysLocalAndOutputIdentifiesUnverifiedEvidence() async throws {
        var requested: URLRequest?
        let tool = NexusReadOnlyLookupTool(networkAllowed: { true }, isAuthorizedURL: { _ in true }, transport: { request, cap in
            requested = request
            XCTAssertEqual(cap, 262_144)
            return NexusLookupResponse(data: Data("金边报告：合计 12。".utf8), url: request.url!, statusCode: 200, mimeType: "text/plain")
        }, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let result = await tool.execute(call(["url": url.absoluteString, "query": "金边"]))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(requested?.httpMethod, "GET")
        XCTAssertEqual(requested?.url, url)
        XCTAssertNil(requested?.httpBody)
        XCTAssertNil(requested?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requested?.value(forHTTPHeaderField: "Cookie"))
        let output = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        XCTAssertEqual(output["sourceID"] as? String, "url:https://example.com/report")
        XCTAssertEqual(output["sourceURL"] as? String, url.absoluteString)
        XCTAssertEqual(output["retrievedAt"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(output["evidenceOnly"] as? Bool, true)
        XCTAssertEqual(output["untrusted"] as? Bool, true)
        XCTAssertEqual(output["verified"] as? Bool, false)
        XCTAssertEqual(output["snippets"] as? [String], ["金边报告：合计 12。"])
    }

    func testNetworkToggleStopsBeforeTransport() async {
        let tool = NexusReadOnlyLookupTool(networkAllowed: { false }, isAuthorizedURL: { _ in true }, transport: { _, _ in
            XCTFail("Disabled networking must never invoke transport")
            throw URLError(.badURL)
        })
        let result = await tool.execute(call())
        XCTAssertFalse(result.succeeded)
    }

    func testHTMLScriptsAreRemovedAndNoMatchIsNotFabricated() async throws {
        let result = await tool("<html><script>私人密码</script><style>密码</style><p>公开报告 &amp; 来源。</p></html>", mime: "text/html").execute(call(["url": url.absoluteString, "query": "密码"]))
        XCTAssertTrue(result.succeeded)
        let output = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        XCTAssertEqual(output["matched"] as? Bool, false)
        XCTAssertEqual(output["snippets"] as? [String], [])
        XCTAssertEqual(NexusReadOnlyLookupTool.documentText("<p>报告 &amp; 来源</p>", mimeType: "text/html"), "报告 & 来源")
    }

    func testRejectsPrivateLocalNumericAndCredentialURLs() throws {
        for raw in ["http://example.com", "https://localhost", "https://report.local", "https://report.internal", "https://127.0.0.1", "https://10.1.2.3", "https://169.254.169.254", "https://[::1]", "https://[fc00::1]", "https://2130706433", "https://0x7f.0.0.1", "https://user:secret@example.com", "https://example.com:8443"] {
            XCTAssertThrowsError(try NexusLookupURLPolicy.validate(URL(string: raw)!), raw)
        }
        XCTAssertEqual(try NexusLookupURLPolicy.validate(URL(string: "https://EXAMPLE.com:443/report#section")!), url)
    }

    func testRedirectPolicyChecksEveryDestinationAndLimitsHops() throws {
        let next = URL(string: "https://example.com/document")!
        XCTAssertEqual(try NexusLookupURLPolicy.redirect(from: url, to: next, hops: 3), next)
        for raw in ["https://other.example.com/report", "http://example.com/report", "https://localhost/report", "https://10.0.0.1/report", "https://example.com:444/report"] {
            XCTAssertThrowsError(try NexusLookupURLPolicy.redirect(from: url, to: URL(string: raw)!, hops: 1))
        }
        XCTAssertThrowsError(try NexusLookupURLPolicy.redirect(from: url, to: next, hops: 4))
    }

    func testDNSAddressClassificationRejectsReservedAndPrivateNetworks() {
        let addresses: [[UInt8]] = [[127, 0, 0, 1], [10, 2, 3, 4], [169, 254, 169, 254], [172, 31, 2, 3], [192, 168, 1, 1], [100, 64, 0, 1], [0, 0, 0, 0], [224, 1, 2, 3], [192, 0, 2, 1], [198, 18, 0, 1], [203, 0, 113, 1]]
        for bytes in addresses {
            XCTAssertFalse(NexusLookupURLPolicy.isPublicIPv4(bytes))
        }
        XCTAssertTrue(NexusLookupURLPolicy.isPublicIPv4([8, 8, 8, 8]))
        XCTAssertFalse(NexusLookupURLPolicy.isPublicIPv6(Array(repeating: 0, count: 16)))
        XCTAssertFalse(NexusLookupURLPolicy.isPublicIPv6([0xfc] + Array(repeating: 0, count: 15)))
        XCTAssertFalse(NexusLookupURLPolicy.isPublicIPv6([0x20, 0x01, 0x0d, 0xb8] + Array(repeating: 0, count: 12)))
        XCTAssertTrue(NexusLookupURLPolicy.isPublicIPv6([0x20, 0x01, 0x48, 0x60] + Array(repeating: 0, count: 12)))
    }

    func testOversizeBinaryAndFailedResponsesAreRejected() async {
        let oversized = await tool(String(repeating: "x", count: NexusReadOnlyLookupTool.maxBytes + 1)).execute(call())
        XCTAssertFalse(oversized.succeeded)
        let binary = await tool("binary", mime: "application/octet-stream").execute(call())
        XCTAssertFalse(binary.succeeded)
        let failed = await tool("not found", status: 404).execute(call())
        XCTAssertFalse(failed.succeeded)
        let empty = await tool("").execute(call())
        XCTAssertFalse(empty.succeeded)
    }

    func testInjectedTransportCannotReturnAnUnauthorizedFinalOrigin() async {
        let tool = NexusReadOnlyLookupTool(networkAllowed: { true }, isAuthorizedURL: { _ in true }, transport: { _, _ in
            NexusLookupResponse(data: Data("untrusted".utf8), url: URL(string: "https://evil.example.com/report")!, statusCode: 200, mimeType: "text/plain")
        })
        let result = await tool.execute(call())
        XCTAssertFalse(result.succeeded)
    }

    func testCancellationIsReportedWithoutSuccessfulEvidence() async {
        let tool = NexusReadOnlyLookupTool(networkAllowed: { true }, isAuthorizedURL: { _ in true }, transport: { _, _ in
            throw CancellationError()
        })
        let result = await tool.execute(call())
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.output.contains("取消"))
        XCTAssertFalse(result.output.contains("sourceID"))
    }

    func testNativeSchemaOnlyAppearsWhenRegistered() {
        var registry = NexusToolRegistry()
        XCTAssertFalse(registry.nativeDefinitions.contains { $0.name == "web_lookup" })
        registry.register(tool())
        let definition = registry.nativeDefinitions.first { $0.name == "web_lookup" }
        XCTAssertEqual(definition?.inputSchema.required, ["url"])
        XCTAssertEqual(Set(definition?.inputSchema.properties.keys.map { $0 } ?? []), Set(["url", "query"]))
        XCTAssertNil(registry.validateNative(call()))
        XCTAssertNotNil(registry.validateNative(call(["url": url.absoluteString, "method": "POST"])))
    }

    func testSnippetBudgetStaysBounded() {
        let snippets = NexusReadOnlyLookupTool.snippets(in: String(repeating: "文", count: 4000), query: "文")
        XCTAssertLessThanOrEqual(snippets.count, 5)
        XCTAssertTrue(snippets.allSatisfy { $0.count <= 728 })
        XCTAssertEqual(NexusReadOnlyLookupTool.snippets(in: String(repeating: "文", count: 4000), query: "").first?.count, 1600)
    }

    private func fixtureConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LookupStreamingProtocol.self]
        return config
    }

    func testProductionDelegateRejectsUndeclaredOversizeStream() async {
        do {
            _ = try await NexusLookupHTTPTransport.fetch(URLRequest(url: URL(string: "https://example.com/oversize")!), maxBytes: 64,
                                                        configuration: fixtureConfiguration(), resolveHost: { _ in })
            XCTFail("The second chunk must exceed the streaming cap")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超过")) }
    }

    func testProductionDelegateDeliversSmallDocument() async throws {
        let response = try await NexusLookupHTTPTransport.fetch(URLRequest(url: url), maxBytes: 64,
                                                               configuration: fixtureConfiguration(), resolveHost: { _ in })
        XCTAssertEqual(String(decoding: response.data, as: UTF8.self), "public document")
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.url, url)
    }

    func testProductionDelegateCancellationStopsPendingRequest() async {
        let started = expectation(description: "document request started")
        let stopped = expectation(description: "document request stopped")
        LookupStreamingProtocol.onStart = { started.fulfill() }
        LookupStreamingProtocol.onStop = { stopped.fulfill() }
        defer { LookupStreamingProtocol.onStart = nil; LookupStreamingProtocol.onStop = nil }
        let configuration = fixtureConfiguration()
        let task = Task {
            try await NexusLookupHTTPTransport.fetch(URLRequest(url: URL(string: "https://example.com/pending")!), maxBytes: 64,
                                                    configuration: configuration, resolveHost: { _ in })
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request must not return evidence") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await fulfillment(of: [stopped], timeout: 2)
    }
}
