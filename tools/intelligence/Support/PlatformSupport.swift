import Foundation
import CoreFoundation

// Apple Foundation 会重导这些函数，Linux 不会；这里转发给真实 CoreFoundation，
// 不改应用源码。
func CFGetTypeID(_ value: AnyObject) -> CFTypeID { CoreFoundation.CFGetTypeID(value) }
func CFBooleanGetTypeID() -> CFTypeID { CoreFoundation.CFBooleanGetTypeID() }

// 平台适配器不替换被测的意图编译、召回、证据审计、推理、执行器、注册表或原生协议。
enum PortableAdapterError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Platform adapter unavailable in portable tests" }
}


enum NexusModelBridge {
    static func complete(_ prompt: String) async throws -> String { throw PortableAdapterError.unavailable }
}


final class NexusKeychain {
    static let shared = NexusKeychain()
    var selectedModel = "portable-fixture"
    var savedConnections: [NexusModelEntry] { [] }
    func key(for id: String) -> String? { nil }
}

enum NexusModelCatalog {
    static var entries: [NexusModelEntry] { [] }
    static func entry(for id: String) -> NexusModelEntry {
        .init(providerID: "fixture", providerType: .openAICompatible,
              providerURL: "https://fixture.invalid/v1", modelID: "fixture", displayName: "fixture", isHidden: false)
    }
}

enum NexusError: LocalizedError {
    case invalidResponse, apiError(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response"
        case .apiError(let message): return message
        }
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var role: String   // "user" | "assistant"
    var content: String
    var createdAt: Date
    var evidence: [String]?

    init(id: UUID = UUID(), role: String, content: String, evidence: [String]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.evidence = evidence
    }
}


// 原生 iSH 运行时在此不可用；事务测试注入文件操作，仍执行真实持久备份与恢复代码。
@MainActor
final class NexusLinuxRuntime {
    static let shared = NexusLinuxRuntime()
    var isExecuting: Bool { false }
    func installedImageRoot() -> URL? { nil }
    func hostWorkspaceURL(for workspace: UUID) -> URL? { nil }
    func ensureWorkspaceReady(workspace: UUID) async throws { throw PortableAdapterError.unavailable }
    func importToWorkspace(data: Data, named: String, workspace: UUID) async throws { throw PortableAdapterError.unavailable }
    func cancelActive(reason: String) {}
    func listWorkspaceFiles(workspace: UUID) async throws -> [NexusWorkspaceFile] { throw PortableAdapterError.unavailable }
    func exportWorkspaceFile(_ path: String, workspace: UUID) async throws -> Data { throw PortableAdapterError.unavailable }
    func deleteWorkspaceFile(_ path: String, workspace: UUID, confirm: String) async throws { throw PortableAdapterError.unavailable }
    func execute(command: String, timeout: Double = 30, workspace: UUID? = nil, confirm: String? = nil,
                 onStatus: ((String) -> Void)? = nil, onOutput: ((String, Bool) -> Void)? = nil) async throws -> NexusLinuxResult {
        throw PortableAdapterError.unavailable
    }
}

struct NexusLinuxResult {
    let output: String
    let errorOutput: String
    let exitCode: Int
    let duration: TimeInterval
    let failure: String?
    var succeeded: Bool { failure == nil && exitCode == 0 }
}

struct NexusWorkspaceFile: Identifiable, Equatable, Sendable {
    var id: String { path }
    let path: String
}

enum NexusWorkspacePath {
    static func sanitizeFileName(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        let cleaned = base.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = cleaned.isEmpty ? "import.bin" : cleaned
        return String(value.prefix(120))
    }

    static func sanitizeRelativePath(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("./") { value = String(value.dropFirst(2)) }
        value = value.replacingOccurrences(of: "\0", with: "")
        let parts = value.split(separator: "/").map(String.init).filter { $0 != ".." && $0 != "." && !$0.isEmpty }
        return parts.joined(separator: "/")
    }
}



// 入口测试注入模型回复。此适配器不发起服务商请求，方法签名匹配应用客户端。
actor NexusClient {
    static let shared = NexusClient()
    init(keyProvider: @escaping (String) -> String? = { _ in nil },
         resolver: @escaping (String) -> NexusModelEntry = { NexusModelCatalog.entry(for: $0) }) {}
    func complete(messages: [ChatMessage], model: String? = nil) async throws -> String { throw PortableAdapterError.unavailable }
    func complete(messages: [ChatMessage], entry: NexusModelEntry, apiKey: String,
                  onDelta: @escaping (String) -> Void = { _ in }) async throws -> String { throw PortableAdapterError.unavailable }
    func nativeTurn(messages: [NexusNativeMessage], tools: [NexusToolDefinition], model: String? = nil) async throws -> NexusNativeReply {
        throw PortableAdapterError.unavailable
    }
}
#if os(Linux)
import FoundationNetworking
// Linux 没有 URLSession.bytes(for:)。旧下载工具仍编译真实实现，
// 此平台方法明确拒绝执行。
typealias URLSession = FoundationNetworking.URLSession
typealias URLRequest = FoundationNetworking.URLRequest
typealias HTTPURLResponse = FoundationNetworking.HTTPURLResponse
extension FoundationNetworking.URLSession {
    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        throw PortableAdapterError.unavailable
    }
}
#endif
