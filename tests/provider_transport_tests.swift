import Foundation

// Only non-transport app dependencies are replaced. URLSession, NexusClient and
// NexusSSEParser below are production implementations; URLProtocol prevents network use.
struct NexusAssistantToolUseBlock: Codable {}
struct NexusToolDefinition: Codable {}
struct NexusToolCall {}
struct NexusToolResult { let callID: UUID; let output: String; let succeeded: Bool }
struct NexusToolResultBlock { let toolUseID: String; let content: String; let isError: Bool }
struct NexusToolResultMessage { let content: [NexusToolResultBlock] }
enum L10n { static func tr(_ key: String, _ args: CVarArg...) -> String { key } }
enum NexusProviderType { case anthropic, openAICompatible }
struct TestModel { let modelID: String; let providerID: String; let providerType: NexusProviderType }
enum NexusModelCatalog {
    static let defaultModelID = "openai-fixture"
    static let entries = [TestModel(modelID: "openai-fixture", providerID: "openai", providerType: .openAICompatible),
                          TestModel(modelID: "anthropic-fixture", providerID: "anthropic", providerType: .anthropic)]
    static func entry(for id: String) -> TestModel { entries.first { $0.modelID == id } ?? entries[0] }
}
final class NexusKeychain: @unchecked Sendable {
    static let shared = NexusKeychain()
    var consent = true
    var key: String? = "fixture-not-a-real-key"
    func hasSharingConsent(for providerID: String) -> Bool { consent }
    func key(for providerID: String) -> String? { key }
}
struct TestAdapter {
    func endpoint(for model: TestModel) -> URL? { URL(string: "https://provider-fixture.invalid/stream") }
    func headers(for model: TestModel, apiKey: String) -> [String: String] { ["Authorization": "Bearer \(apiKey)"] }
}
enum NexusProviderRequestBuilder {
    static func adapter(for model: TestModel) -> TestAdapter { TestAdapter() }
    static func body(model: TestModel, messages: [ChatMessage]) throws -> Data { Data("{}".utf8) }
}

final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static var body = Data()
    static var status = 200
    static var mime = "text/event-stream"
    static var hang = false
    static let probe = NetworkProbe()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.probe.start()
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": Self.mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Split through UTF-8, JSON strings and CRLF boundaries, as a network can.
        for byte in Self.body { client?.urlProtocol(self, didLoad: Data([byte])) }
        if !Self.hang { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { Self.probe.stop() }
}
final class NetworkProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var stops = 0
    func start() { lock.lock(); count += 1; lock.unlock() }
    func stop() { lock.lock(); stops += 1; lock.unlock() }
    var snapshot: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (count, stops) }
}
final class CallbackProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var output = ""
    private var completions = 0
    private var errors = [Error]()
    func delta(_ text: String) { lock.lock(); output += text; lock.unlock() }
    func complete() { lock.lock(); completions += 1; lock.unlock() }
    func error(_ error: Error) { lock.lock(); errors.append(error); lock.unlock() }
    var snapshot: (output: String, completions: Int, errors: [Error]) {
        lock.lock(); defer { lock.unlock() }; return (output, completions, errors)
    }
}

@main struct ProviderTests {
    static var assertions = 0
    static func expect(_ value: Bool, _ message: String) {
        assertions += 1
        guard value else { fatalError("FAILED: \(message)") }
    }
    static func parsed(_ body: String, format: NexusSSEFormat, limit: Int = 64_000) throws -> String {
        var parser = NexusSSEParser(format: format, maxResponseCharacters: limit)
        var output = ""
        for byte in body.utf8 { if let delta = try parser.consume(byte) { output += delta } }
        try parser.finish()
        return output
    }
    static func fails(_ body: String, format: NexusSSEFormat, error expected: NexusStreamError, limit: Int = 64_000) {
        do { _ = try parsed(body, format: format, limit: limit); expect(false, "expected \(expected)") }
        catch { expect(error as? NexusStreamError == expected, "received \(error), expected \(expected)") }
    }
    static func client(timeout: TimeInterval = 1, limit: Int = 64_000) -> NexusClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return NexusClient(configuration: config, timeout: timeout, maxResponseCharacters: limit)
    }
    static func run(_ client: NexusClient, model: String = "openai-fixture", probe: CallbackProbe = CallbackProbe()) async -> CallbackProbe {
        await client.streamChat(messages: [ChatMessage(role: "user", content: "fixture")], model: model,
                                onDelta: { probe.delta($0) }, onComplete: { probe.complete() }, onError: { probe.error($0) })
        return probe
    }
    static func setup(_ body: String, status: Int = 200, mime: String = "text/event-stream", hang: Bool = false) {
        FixtureProtocol.body = Data(body.utf8); FixtureProtocol.status = status; FixtureProtocol.mime = mime; FixtureProtocol.hang = hang
        NexusKeychain.shared.consent = true; NexusKeychain.shared.key = "fixture-not-a-real-key"
    }
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let anthropic = try String(contentsOf: directory.appendingPathComponent("anthropic_success.sse"), encoding: .utf8)
        let openai = try String(contentsOf: directory.appendingPathComponent("openai_success.sse"), encoding: .utf8)
        let overloaded = try String(contentsOf: directory.appendingPathComponent("anthropic_error.sse"), encoding: .utf8)
        expect(try parsed(anthropic, format: .anthropic) == "你好 👋", "Anthropic documented sequence/multiline/no space/UTF-8")
        expect(try parsed(openai, format: .openAICompatible) == "Hello world", "OpenAI finish/usage/DONE")
        expect(try parsed("\u{FEFF}" + anthropic.replacingOccurrences(of: "\n", with: "\r\n"), format: .anthropic) == "你好 👋", "BOM and CRLF")
        expect(try parsed(openai.replacingOccurrences(of: "\n", with: "\r"), format: .openAICompatible) == "Hello world", "CR-only framing")
        fails(overloaded, format: .anthropic, error: .providerError("overloaded_error"))
        fails(openai.replacingOccurrences(of: "\"stop\"", with: "\"length\""), format: .openAICompatible, error: .truncated)
        fails(anthropic.replacingOccurrences(of: "end_turn", with: "max_tokens"), format: .anthropic, error: .truncated)
        fails(openai.replacingOccurrences(of: "\"stop\"", with: "\"content_filter\""), format: .openAICompatible, error: .refused)
        fails(openai.replacingOccurrences(of: "\"stop\"", with: "\"tool_calls\""), format: .openAICompatible, error: .unsupportedToolCall)
        fails(openai.replacingOccurrences(of: "data:[DONE]\n\n", with: ""), format: .openAICompatible, error: .unexpectedEnd)
        fails(openai.trimmingCharacters(in: .newlines), format: .openAICompatible, error: .unexpectedEnd)
        fails("data:[DONE]\n\n", format: .openAICompatible, error: .unexpectedEnd)
        fails("data:{broken}\n\n", format: .openAICompatible, error: .malformedEvent)
        fails(openai, format: .openAICompatible, error: .responseTooLarge, limit: 4)
        fails(openai.replacingOccurrences(of: "Hello ", with: "").replacingOccurrences(of: "world", with: ""), format: .openAICompatible, error: .emptyResponse)
        fails("data:{\"error\":{\"type\":\"rate_limit_error\",\"message\":\"secret\"}}\n\n", format: .openAICompatible, error: .providerError("rate_limit_error"))
        fails(openai.replacingOccurrences(of: "\"content\":\"world\"", with: "\"tool_calls\":[{\"index\":0,\"function\":{\"name\":\"write_file\"}}]"), format: .openAICompatible, error: .unsupportedToolCall)
        fails(openai.replacingOccurrences(of: "\"content\":\"world\"", with: "\"content\":123"), format: .openAICompatible, error: .malformedEvent)
        fails(anthropic.replacingOccurrences(of: "event:message_stop\ndata:{\"type\":\"message_stop\"}\n\n", with: ""), format: .anthropic, error: .unexpectedEnd)
        fails(anthropic.replacingOccurrences(of: "\"type\":\"text\",\"text\":\"\"", with: "\"type\":\"tool_use\",\"name\":\"write_file\""), format: .anthropic, error: .unsupportedToolCall)
        var invalidUTF8 = NexusSSEParser(format: .openAICompatible)
        do { for byte: UInt8 in [0x64, 0x61, 0x74, 0x61, 0x3A, 0xFF, 0x0A] { _ = try invalidUTF8.consume(byte) }; expect(false, "invalid UTF-8") }
        catch { expect(error as? NexusStreamError == .malformedEvent, "invalid UTF-8 fails") }
        var bounded = NexusSSEParser(format: .openAICompatible, maxEventBytes: 8)
        do { for byte in "data:123456789".utf8 { _ = try bounded.consume(byte) }; expect(false, "long line") }
        catch { expect(error as? NexusStreamError == .responseTooLarge, "line bounded before newline") }
        var wireBounded = NexusSSEParser(format: .openAICompatible, maxWireBytes: 8)
        do { for byte in ":ping\n\n:ping\n\n".utf8 { _ = try wireBounded.consume(byte) }; expect(false, "wire limit") }
        catch { expect(error as? NexusStreamError == .responseTooLarge, "comments count toward wire limit") }

        setup(openai)
        let success = await run(client()).snapshot
        expect(success.output == "Hello world" && success.completions == 1 && success.errors.isEmpty, "production transport success exactly once")
        setup(anthropic)
        let claude = await run(client(), model: "anthropic-fixture").snapshot
        expect(claude.output == "你好 👋" && claude.completions == 1 && claude.errors.isEmpty, "production Anthropic transport")
        setup(overloaded)
        let serverError = await run(client(), model: "anthropic-fixture").snapshot
        expect(serverError.completions == 0 && serverError.errors.count == 1, "partial SSE error never completes")
        setup(openai.replacingOccurrences(of: "data:[DONE]\n\n", with: ""))
        let eof = await run(client()).snapshot
        expect(eof.completions == 0 && eof.errors.first as? NexusStreamError == .unexpectedEnd, "EOF never claims success")
        setup(openai, status: 429)
        let http = await run(client()).snapshot
        expect(http.completions == 0 && http.errors.count == 1 && http.output.isEmpty, "HTTP error never emits body")
        setup(openai, mime: "application/json")
        let mime = await run(client()).snapshot
        expect(mime.completions == 0 && mime.errors.count == 1, "non-SSE HTTP 200 rejected")
        setup(openai)
        let large = await run(client(limit: 4)).snapshot
        expect(large.completions == 0 && large.errors.first as? NexusStreamError == .responseTooLarge, "transport output limit")
        setup("", hang: true)
        let timeout = await run(client(timeout: 0.05)).snapshot
        expect(timeout.completions == 0 && timeout.errors.count == 1 && timeout.errors.first as? NexusStreamError == .timedOut, "hard deadline closes silent HTTP body exactly once")
        setup("data:{\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}]}\n\n", hang: true)
        let cancelProbe = CallbackProbe()
        let task = Task { await run(client(), probe: cancelProbe) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        _ = await task.value
        let cancelled = cancelProbe.snapshot
        expect(cancelled.completions == 0 && cancelled.errors.count == 1 && cancelled.errors[0] is CancellationError, "cancellation cannot produce partial success")
        setup(openai)
        let before = FixtureProtocol.probe.snapshot.0
        NexusKeychain.shared.consent = false
        let noConsent = await run(client()).snapshot
        expect(noConsent.errors.count == 1 && noConsent.completions == 0 && FixtureProtocol.probe.snapshot.0 == before, "no provider request without consent")
        let policy = NexusProviderSessionDelegate(origin: URL(string: "https://provider-fixture.invalid/v1")!)
        expect(policy.allows(URL(string: "https://provider-fixture.invalid/other")), "same-origin redirect allowed")
        expect(!policy.allows(URL(string: "https://elsewhere.invalid/stream")), "credential cannot follow cross-host redirect")
        expect(!policy.allows(URL(string: "http://provider-fixture.invalid/stream")), "credential cannot follow HTTPS downgrade")
        expect(!policy.allows(URL(string: "https://provider-fixture.invalid:444/stream")), "credential cannot follow cross-port redirect")
        print("PASS: \(assertions) provider parser/transport assertions; no network or API credentials used.")
    }
}
