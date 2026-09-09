import XCTest
import Security
@testable import BlackGod

private struct APIScript {
    var status = 200
    var contentType = "text/event-stream"
    var body: String
    var failure: URLError?
    var holdOpen = false
}

private final class APIProtocol: URLProtocol {
    static let lock = NSLock()
    static var scripts: [String: APIScript] = [:]
    static var requests: [String: URLRequest] = [:]
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.url!.pathComponents[1]
        let script = Self.lock.withLock { Self.requests[id] = request; return Self.scripts[id]! }
        if let failure = script.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: script.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": script.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // 把中文 UTF-8 拆成单字节，验证真实 URLSession 读取能跨网络分片重组。
        for byte in script.body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        if !script.holdOpen { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}

final class NexusAPITests: XCTestCase {
    private func client(_ script: APIScript, type: NexusProviderType = .openAICompatible, key: String? = "fixture-key") -> (NexusClient, String) {
        let id = UUID().uuidString
        APIProtocol.lock.withLock { APIProtocol.scripts[id] = script }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIProtocol.self]
        let model = NexusModelEntry(providerID: "fixture", providerType: type, providerURL: "https://fixture.invalid/\(id)/v1", modelID: "test-model", displayName: "测试", isHidden: false)
        return (NexusClient(session: URLSession(configuration: configuration), keyProvider: { _ in key }, resolver: { _ in model }, consentValidator: { _ in }), id)
    }
    private let messages = [ChatMessage(role: "user", content: "测试请求")]
    private let openAIStream = "data:{\"choices\":[{\"delta\":{\"content\":\"你好\"},\"finish_reason\":null}]}\r\n\r\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"

    func testNativeTransportBothProtocolsAndToolResultRoundTrip() async throws {
        for type in [NexusProviderType.openAICompatible, .anthropic] {
            let body = type == .anthropic
                ? "{\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_fixture\",\"name\":\"calc\",\"input\":{\"expression\":\"3+4\"}}],\"stop_reason\":\"tool_use\"}"
                : "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"tool_calls\":[{\"id\":\"call_fixture\",\"type\":\"function\",\"function\":{\"name\":\"calc\",\"arguments\":\"{\\\"expression\\\":\\\"3+4\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}"
            let (client, id) = client(APIScript(contentType: "application/json", body: body), type: type)
            var registry = NexusToolRegistry()
            registry.register(NexusCalculatorTool())
            let initial: [NexusNativeMessage] = [.text(role: "user", content: "计算3+4")]
            let reply = try await client.nativeTurn(messages: initial, tools: registry.nativeDefinitions)
            let native = try XCTUnwrap(reply.calls.first)
            let result = await registry.execute(native.call)
            XCTAssertEqual(result.output, "7")
            let request = try XCTUnwrap(APIProtocol.lock.withLock { APIProtocol.requests[id] })
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            let finalBody = type == .anthropic
                ? "{\"content\":[{\"type\":\"text\",\"text\":\"7\"}],\"stop_reason\":\"end_turn\"}"
                : "{\"choices\":[{\"message\":{\"content\":\"7\"},\"finish_reason\":\"stop\"}]}"
            APIProtocol.lock.withLock { APIProtocol.scripts[id] = APIScript(contentType: "application/json", body: finalBody) }
            let final = try await client.nativeTurn(messages: initial + [.assistant(reply), .results([(native, result)])], tools: registry.nativeDefinitions)
            XCTAssertEqual(final.text, "7")
            XCTAssertTrue(final.calls.isEmpty)
        }
    }

    func testNativeTransportRejectsErrorsAndHonorsCancellation() async throws {
        for script in [APIScript(status: 401, body: "{\"error\":{\"message\":\"fixture-key\"}}"),
                       APIScript(contentType: "text/html", body: "wrong"), APIScript(contentType: "application/json", body: "{")] {
            let (client, _) = client(script)
            do { _ = try await client.nativeTurn(messages: [.text(role: "user", content: "test")], tools: []); XCTFail("无效响应") }
            catch { XCTAssertFalse(error.localizedDescription.contains("fixture-key")) }
        }
        let (client, id) = client(APIScript(contentType: "application/json", body: "{", holdOpen: true))
        let task = Task { try await client.nativeTurn(messages: [.text(role: "user", content: "test")], tools: []) }
        for _ in 0..<100 {
            if APIProtocol.lock.withLock({ APIProtocol.requests[id] != nil }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(APIProtocol.lock.withLock { APIProtocol.requests[id] })
        task.cancel()
        do { _ = try await task.value; XCTFail("应取消") } catch is CancellationError {} catch { XCTFail("取消类型错误") }
    }

    func testOpenAITransportHeadersUTF8AndCompletion() async throws {
        let (client, id) = client(APIScript(body: openAIStream))
        let text = try await client.complete(messages: messages, model: "test-model")
        XCTAssertEqual(text, "你好")
        let request = APIProtocol.lock.withLock { APIProtocol.requests[id] }
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        XCTAssertNil(request?.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertTrue(request?.url?.path.hasSuffix("/v1/chat/completions") == true)
    }

    func testAnthropicTransportHeadersAndEvents() async throws {
        let stream = "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"完成\"}}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"
        let (client, id) = client(APIScript(body: stream), type: .anthropic)
        let text = try await client.complete(messages: messages, model: "test-model")
        XCTAssertEqual(text, "完成")
        let request = APIProtocol.lock.withLock { APIProtocol.requests[id] }
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "fixture-key")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(request?.url?.path.hasSuffix("/v1/messages") == true)
    }

    func testNonStreamingCompatibilityResponse() async throws {
        let (client, _) = client(APIScript(contentType: "application/json", body: "{\"choices\":[{\"message\":{\"content\":\"完整答复\",\"tool_calls\":null},\"finish_reason\":\"stop\"}]}"))
        let output = try await client.complete(messages: messages)
        XCTAssertEqual(output, "完整答复")
        let (anthropic, _) = self.client(APIScript(contentType: "application/json", body: "{\"content\":[{\"type\":\"text\",\"text\":\"完整答复\"}],\"stop_reason\":\"end_turn\"}"), type: .anthropic)
        let answer = try await anthropic.complete(messages: messages)
        XCTAssertEqual(answer, "完整答复")
    }

    func testHTTPFailuresAndCredentialRedaction() async {
        for status in [301, 401, 403, 404, 429, 500, 529] {
            let (client, _) = client(APIScript(status: status, contentType: "application/json", body: "{\"error\":{\"message\":\"bad fixture-key\"}}"))
            do { _ = try await client.complete(messages: messages); XCTFail("HTTP \(status) 不应成功") }
            catch {
                XCTAssertTrue(error.localizedDescription.contains("HTTP \(status)"))
                XCTAssertFalse(error.localizedDescription.contains("fixture-key"))
            }
        }
    }

    func testInStreamErrorDoesNotReturnPartialSuccess() async {
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"未完成\"}}]}\n\ndata: {\"error\":{\"message\":\"服务繁忙\"}}\n\ndata: [DONE]\n\n"
        let (client, _) = client(APIScript(body: body))
        do { _ = try await client.complete(messages: messages); XCTFail("流中错误不应成功") }
        catch { XCTAssertTrue(error.localizedDescription.contains("服务繁忙")) }
    }

    func testEOFWithoutCompletionFails() async {
        let (client, _) = client(APIScript(body: "data: {\"choices\":[{\"delta\":{\"content\":\"半句话\"}}]}\n\n"))
        do { _ = try await client.complete(messages: messages); XCTFail("截断不应成功") }
        catch { XCTAssertTrue(error.localizedDescription.contains("中断")) }
    }

    func testOutputLimitAndContentFilterFail() async {
        for reason in ["length", "content_filter", "tool_calls"] {
            let (client, _) = client(APIScript(body: "data: {\"choices\":[{\"delta\":{\"content\":\"部分结果\"},\"finish_reason\":\"\(reason)\"}]}\n\ndata: [DONE]\n\n"))
            do { _ = try await client.complete(messages: messages); XCTFail(reason) } catch {}
        }
    }

    func testEmptyWrongContentAndMalformedStreamsFail() async {
        for script in [APIScript(body: "data: [DONE]\n\n"), APIScript(contentType: "text/html", body: "<html>登录页面</html>"), APIScript(body: "data: {broken}\n\n")] {
            let (client, _) = client(script)
            do { _ = try await client.complete(messages: messages); XCTFail("无效响应不应成功") } catch {}
        }
    }

    func testMissingKeyDoesNotSendRequest() async {
        let (client, id) = client(APIScript(body: openAIStream), key: nil)
        do { _ = try await client.complete(messages: messages); XCTFail("缺少密钥不应发送") } catch {}
        XCTAssertNil(APIProtocol.lock.withLock { APIProtocol.requests[id] })
    }

    func testCancelledTaskDoesNotSendRequest() async {
        let (client, id) = client(APIScript(body: openAIStream))
        let task = Task {
            try await Task.sleep(for: .milliseconds(20))
            return try await client.complete(messages: messages)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("取消不应成功") } catch is CancellationError {} catch { XCTFail("取消类型错误") }
        XCTAssertNil(APIProtocol.lock.withLock { APIProtocol.requests[id] })
    }

    func testCancellationDuringNetworkStream() async throws {
        let (client, id) = client(APIScript(body: "data: {\"choices\":[{\"delta\":{\"content\":\"开始\"}}]}\n\n", holdOpen: true))
        let task = Task { try await client.complete(messages: messages) }
        for _ in 0..<100 {
            if APIProtocol.lock.withLock({ APIProtocol.requests[id] != nil }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(APIProtocol.lock.withLock { APIProtocol.requests[id] })
        task.cancel()
        do { _ = try await task.value; XCTFail("传输中取消不应成功") }
        catch is CancellationError {} catch { XCTFail("取消应明确传播") }
    }

    func testProviderRequestBodiesAndRoutes() throws {
        for entry in NexusModelCatalog.entries {
            let request = try NexusProviderRequestBuilder.request(model: entry, messages: messages, apiKey: "fixture-key")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, entry.modelID)
            XCTAssertEqual(body["stream"] as? Bool, true)
            XCTAssertNil(body["tools"])
            XCTAssertEqual((body["messages"] as? [[String: Any]])?.first?["content"] as? String, "测试请求")
            if entry.providerType == .anthropic { XCTAssertEqual(body["max_tokens"] as? Int, 4096) }
            XCTAssertEqual(request.url?.scheme, "https")
        }
    }

    func testUnknownModelDoesNotSilentlyUseAnthropic() {
        let entry = NexusModelCatalog.entry(for: "unconfigured-model-" + UUID().uuidString)
        XCTAssertEqual(entry.providerID, "unconfigured")
        XCTAssertNil(NexusEndpoint.url(base: entry.providerURL, type: entry.providerType))
    }

    func testTransportTimeoutIsReported() async {
        let (client, _) = client(APIScript(body: "", failure: URLError(.timedOut)))
        do { _ = try await client.complete(messages: messages); XCTFail("超时不应成功") } catch {}
    }

    func testEndpointNormalizationAndRejectedDestinations() {
        XCTAssertEqual(NexusEndpoint.url(base: "https://example.com/v1/", type: .anthropic)?.path, "/v1/messages")
        XCTAssertEqual(NexusEndpoint.url(base: "https://example.com/v1/messages", type: .anthropic)?.path, "/v1/messages")
        XCTAssertEqual(NexusEndpoint.url(base: "https://example.com/v1/chat/completions/", type: .openAICompatible)?.path, "/v1/chat/completions")
        for base in ["http://example.com", "https://key@example.com", "https://example.com?key=secret", "https://example.com#fragment", ""] {
            XCTAssertNil(NexusEndpoint.url(base: base, type: .openAICompatible))
        }
        XCTAssertNotEqual(NexusEndpoint.credentialID(base: "https://one.example/v1", type: .openAICompatible), NexusEndpoint.credentialID(base: "https://two.example/v1", type: .openAICompatible))
    }

    func testMultilineSSEEvent() throws {
        var decoder = NexusSSEDecoder()
        var events: [String] = []
        for byte in ": heartbeat\r\nevent: message\r\ndata: {\r\ndata: \"hello\":\"中文\"}\r\n\r\n".utf8 {
            if let event = try decoder.append(byte) { events.append(event) }
        }
        XCTAssertEqual(events, ["{\n\"hello\":\"中文\"}"])
    }

    func testKeychainConnectionPersistenceAndProviderIsolation() throws {
        let service = "blackgod.tests." + UUID().uuidString
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
        let keychain = NexusKeychain(service: service)
        let entry = NexusModelEntry(providerID: "isolated-provider", providerType: .openAICompatible, providerURL: "https://fixture.invalid/v1", modelID: "fixture-model", displayName: "测试", isHidden: false)
        do { try keychain.saveConnection(entry, apiKey: "fixture-value") }
        catch { print("KEYCHAIN_WRITE_DIAGNOSTIC code=\((error as NSError).code)"); throw error }
        XCTAssertEqual(keychain.selectedConnection, entry)
        XCTAssertEqual(keychain.selectedModel, "fixture-model")
        XCTAssertEqual(keychain.key(for: entry.providerID), "fixture-value")
        XCTAssertNil(keychain.key(for: "other-provider"))
        let other = NexusModelEntry(providerID: "other-provider", providerType: .anthropic, providerURL: "https://other.invalid", modelID: "other-model", displayName: "其他", isHidden: false)
        try keychain.saveConnection(other, apiKey: "other-value")
        let reloaded = NexusKeychain(service: service)
        XCTAssertEqual(reloaded.selectedConnection, other)
        XCTAssertEqual(reloaded.selectedModel, "other-model")
        XCTAssertEqual(reloaded.key(for: entry.providerID), "fixture-value")
        XCTAssertEqual(reloaded.key(for: other.providerID), "other-value")
        let invalid = NexusModelEntry(providerID: "other-provider", providerType: .anthropic, providerURL: "http://invalid", modelID: "bad", displayName: "无效", isHidden: false)
        XCTAssertThrowsError(try keychain.saveConnection(invalid, apiKey: "replacement"))
        XCTAssertEqual(reloaded.selectedConnection, other)
        XCTAssertEqual(reloaded.key(for: other.providerID), "other-value")
        try keychain.saveConnection(entry, apiKey: "")
        XCTAssertNil(keychain.key(for: entry.providerID))
    }

    func testCredentialAvailabilityReport() {
        // 仅报告凭据有无，绝不输出值；不自动发起付费真实请求。
        let entries = NexusModelCatalog.entries + (NexusKeychain.shared.selectedConnection.map { [$0] } ?? [])
        var seen = Set<String>()
        for entry in entries where seen.insert(entry.credentialID).inserted {
            print("API_CREDENTIAL_STATUS \(entry.providerID) configured=\(!(NexusKeychain.shared.key(for: entry.credentialID) ?? "").isEmpty)")
        }
    }
}


extension NexusAPITests {
    func testGeminiAndResponsesTransportAndNativeRoundTrip() async throws {
        let scripts: [(NexusProviderType, String, String)] = [
            (.gemini, #"{"candidates":[{"finishReason":"STOP","content":{"role":"model","parts":[{"functionCall":{"name":"calc","args":{"expression":"3+4"},"id":"gem-call"},"thoughtSignature":"opaque-signature"}]}}]}"#,
             #"{"candidates":[{"finishReason":"STOP","content":{"role":"model","parts":[{"text":"7"}]}}]}"#),
            (.responses, #"{"status":"completed","error":null,"output":[{"type":"reasoning","id":"reasoning-1","summary":[],"encrypted_content":"opaque-encrypted"},{"type":"function_call","id":"fc-1","call_id":"resp-call","name":"calc","arguments":"{\"expression\":\"3+4\"}"}]}"#,
             #"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"7"}]}]}"#)
        ]
        for (type, first, last) in scripts {
            let (client, id) = client(APIScript(contentType: "application/json", body: first), type: type)
            var tools = NexusToolRegistry()
            tools.register(NexusCalculatorTool())
            let initial: [NexusNativeMessage] = [.text(role: "user", content: "计算3+4")]
            let reply = try await client.nativeTurn(messages: initial, tools: tools.nativeDefinitions)
            let call = try XCTUnwrap(reply.calls.first)
            let result = await tools.execute(call.call)
            XCTAssertEqual(result.output, "7")
            APIProtocol.lock.withLock { APIProtocol.scripts[id] = APIScript(contentType: "application/json", body: last) }
            let final = try await client.nativeTurn(messages: initial + [.assistant(reply), .results([(call, result)])], tools: tools.nativeDefinitions)
            XCTAssertEqual(final.text, "7")
            let request = try XCTUnwrap(APIProtocol.lock.withLock { APIProtocol.requests[id] })
            // URLSession moves the body to a stream, so replay correctness is checked via the codec.
            let entry = NexusModelEntry(providerID: "fixture", providerType: type, providerURL: "https://fixture.invalid/" + id + "/v1", modelID: "test-model", displayName: "测试", isHidden: false)
            let data = try NexusNativeCodec.body(model: entry, messages: initial + [.assistant(reply), .results([(call, result)])], tools: tools.nativeDefinitions)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let raw = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(raw.contains(call.providerID))
            if type == .gemini {
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertTrue(request.url?.path.hasSuffix("/models/test-model:generateContent") == true)
                XCTAssertNotNil(body["contents"])
                XCTAssertTrue(raw.contains("opaque-signature"))
                XCTAssertTrue(raw.contains("functionResponse"))
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
                XCTAssertTrue(request.url?.path.hasSuffix("/responses") == true)
                XCTAssertEqual(body["store"] as? Bool, false)
                XCTAssertNotNil(body["input"])
                XCTAssertTrue(raw.contains("opaque-encrypted"))
                XCTAssertTrue(raw.contains("function_call_output"))
            }
            let answer = try await client.complete(messages: messages)
            XCTAssertEqual(answer, "7")
        }
    }

    func testModelDiscoveryFormatsAndAuthenticatedTransport() async throws {
        for type in [NexusProviderType.anthropic, .openAICompatible, .gemini, .responses] {
            let body = type == .gemini
                ? #"{"models":[{"name":"models/chat-test","displayName":"Chat","supportedGenerationMethods":["generateContent"]},{"name":"models/embedding-test","supportedGenerationMethods":["embedContent"]}]}"#
                : #"{"data":[{"id":"chat-test","display_name":"Chat"},{"id":"chat-test"}]}"#
            let (client, id) = client(APIScript(contentType: "application/json", body: body), type: type)
            let entry = NexusModelEntry(providerID: "fixture", providerType: type, providerURL: "https://fixture.invalid/" + id + "/v1", modelID: "", displayName: "", isHidden: false)
            let models = try await client.fetchModels(entry: entry, apiKey: "fixture-key")
            XCTAssertEqual(models.map(\.id), ["chat-test"])
            let request = try XCTUnwrap(APIProtocol.lock.withLock { APIProtocol.requests[id] })
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.path.hasSuffix("/models") == true)
            XCTAssertNil(request.url?.query)
        }
    }

    func testNewProtocolsRejectIncompleteOrBlockedResponses() throws {
        for status in ["incomplete", "failed", "queued", "in_progress"] {
            XCTAssertThrowsError(try NexusNativeCodec.decode(Data("{\"status\":\"\(status)\",\"output\":[]}".utf8), type: .responses))
        }
        for status in ["MAX_TOKENS", "SAFETY", "MALFORMED_FUNCTION_CALL"] {
            let body = "{\"candidates\":[{\"finishReason\":\"\(status)\",\"content\":{\"parts\":[{\"text\":\"partial\"}]}}]}"
            XCTAssertThrowsError(try NexusNativeCodec.decode(Data(body.utf8), type: .gemini))
        }
    }

    func testMultipleConnectionsToSameProviderKeepCredentialsSeparate() throws {
        let service = "blackgod.tests." + UUID().uuidString
        defer { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
        let keychain = NexusKeychain(service: service)
        let a = NexusModelEntry(providerID: "opengpt", providerType: .responses, providerURL: "https://a.invalid/v1", modelID: "same-model", displayName: "账号A", isHidden: false, connectionID: "account-a")
        let b = NexusModelEntry(providerID: "opengpt", providerType: .responses, providerURL: "https://b.invalid/v1", modelID: "same-model", displayName: "账号B", isHidden: false, connectionID: "account-b")
        try keychain.saveConnection(a, apiKey: "fixture-a")
        try keychain.saveConnection(b, apiKey: "fixture-b")
        XCTAssertEqual(keychain.savedConnections.count, 2)
        XCTAssertEqual(keychain.key(for: a.credentialID), "fixture-a")
        XCTAssertEqual(keychain.key(for: b.credentialID), "fixture-b")
        try keychain.selectConnection(id: a.id)
        XCTAssertEqual(keychain.selectedConnection, a)
        XCTAssertThrowsError(try keychain.selectConnection(id: "missing"))
        XCTAssertEqual(keychain.selectedConnection, a)
    }

    func testProviderPresetsResolveOfficialPathsWithoutInventedModels() throws {
        let expected: [String: String] = ["kimi-oauth": "/coding/v1/chat/completions", "grok-oauth": "/v1/chat/completions", "minimax-oauth": "/anthropic/v1/messages", "minimax-cn-oauth": "/anthropic/v1/messages", "openrouter": "/api/v1/chat/completions", "opengpt": "/v1/responses", "anthropic": "/v1/messages", "gemini": "/v1beta/models/test-model:generateContent", "volcengine": "/api/v3/chat/completions", "deepseek": "/v1/chat/completions", "zhipu": "/api/paas/v4/chat/completions", "moonshot": "/v1/chat/completions", "minimax": "/v1/chat/completions", "hunyuan": "/v1/chat/completions", "xai": "/v1/chat/completions"]
        for preset in NexusProviderPresets.all {
            XCTAssertEqual(preset.entry.modelID, "")
            if preset.id == "dashscope" { XCTAssertEqual(preset.baseURL, ""); continue }
            let entry = NexusModelEntry(providerID: preset.id, providerType: preset.type, providerURL: preset.baseURL, modelID: "test-model", displayName: preset.name, isHidden: false)
            XCTAssertEqual(NexusEndpoint.requestURL(for: entry)?.path, expected[preset.id])
        }
        XCTAssertEqual(NexusProviderPresets.all.count, 16)
    }
}
