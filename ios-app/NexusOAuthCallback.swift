import Foundation
import Network

/// A bounded, one-shot HTTP receiver bound only to IPv4 loopback, never LAN.
@MainActor
final class NexusOAuthCallback {
    private var listener: NWListener?
    private var ready: CheckedContinuation<UInt16, Error>?
    private var waiter: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var connections: [UUID: NWConnection] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private var timeout: Task<Void, Never>?
    private var port: UInt16 = 0
    private let attempt: NexusOAuthAttempt
    init(attempt: NexusOAuthAttempt) { self.attempt = attempt }

    func start(timeoutSeconds: Double = 300) async throws -> UInt16 {
        guard listener == nil, result == nil else { throw NexusOAuthError.unavailable }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.result == nil else { return }
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else { self.finish(.failure(NexusOAuthError.unavailable)); return }
                    self.port = port; self.ready?.resume(returning: port); self.ready = nil
                case .failed: self.finish(.failure(NexusOAuthError.unavailable))
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return }
            self?.finish(.failure(NexusOAuthError.expired))
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                ready = continuation; listener.start(queue: .main)
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    func waitForCode() async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if let result { return try result.get() }
            guard waiter == nil else { throw NexusOAuthError.unavailable }
            return try await withCheckedThrowingContinuation { waiter = $0 }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ outcome: Result<String, Error>) {
        guard result == nil else { return }
        result = outcome
        timeout?.cancel(); timeout = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        for task in deadlines.values { task.cancel() }
        deadlines.removeAll()
        if let ready { ready.resume(throwing: outcome.failure ?? NexusOAuthError.unavailable); self.ready = nil }
        waiter?.resume(with: outcome); waiter = nil
    }
    private func accept(_ connection: NWConnection) {
        guard result == nil, connections.count < 4 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: .main)
        deadlines[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.close(id)
        }
        receive(connection, id: id, accumulated: Data())
    }
    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
        deadlines.removeValue(forKey: id)?.cancel()
    }
    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var buffer = accumulated; if let data { buffer.append(data) }
                guard buffer.count <= 8192 else { self.respond(connection, id: id, status: 431); return }
                if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                    do {
                        let url = try Self.callbackURL(request: buffer, port: self.port)
                        let code = try self.attempt.code(from: url, port: self.port)
                        self.respond(connection, id: id, status: 200)
                        self.finish(.success(code))
                    } catch NexusOAuthError.denied {
                        self.respond(connection, id: id, status: 200); self.finish(.failure(NexusOAuthError.denied))
                    } catch { self.respond(connection, id: id, status: 400) }
                } else if complete || error != nil { self.close(id) }
                else { self.receive(connection, id: id, accumulated: buffer) }
            }
        }
    }
    private func respond(_ connection: NWConnection, id: UUID, status: Int) {
        connections.removeValue(forKey: id); deadlines.removeValue(forKey: id)?.cancel()
        let body = status == 200 ? "授权结果已收到，请返回 Black God。" : "此请求不是有效的登录回调。"
        let bytes = Data(body.utf8)
        let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
    }
    nonisolated static func callbackURL(request data: Data, port: UInt16) throws -> URL {
        guard data.count <= 8192, let text = String(data: data, encoding: .utf8),
              let end = text.range(of: "\r\n\r\n") else { throw NexusOAuthError.invalidCallback }
        let lines = text[..<end.lowerBound].components(separatedBy: "\r\n")
        let first = lines[0].components(separatedBy: " ")
        guard first.count == 3, first[0] == "GET", first[2] == "HTTP/1.1", first[1].hasPrefix("/"), !first[1].hasPrefix("//") else { throw NexusOAuthError.invalidCallback }
        let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }.map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        guard hosts == ["localhost:\(port)"], let url = URL(string: "http://localhost:\(port)" + first[1]) else { throw NexusOAuthError.invalidCallback }
        return url
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let error) = self { return error }; return nil }
}
