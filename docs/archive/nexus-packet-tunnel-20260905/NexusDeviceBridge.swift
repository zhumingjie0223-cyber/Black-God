//
// NexusDeviceBridge.swift — 受控 iOS 设备 Shell relay
//
// 本类只实现与 Cloudflare 神枢现有 device_shell_register/shell_exec/shell_result 帧兼容的桥接。
// iOS App 本身不包含 iSH/PRoot 内核；若没有显式注入经审计的 NexusShellExecutor，
// 收到 shell_exec 必须返回 unavailable，绝不能编造成功或声称操作了手机网卡。

import Foundation

struct NexusShellResult: Sendable {
    let ok: Bool
    let stdout: String
    let stderr: String
    let exitCode: Int
}

protocol NexusShellExecutor: Sendable {
    func execute(code: String, language: String, timeoutSeconds: Int) async -> NexusShellResult
}

struct UnavailableNexusShellExecutor: NexusShellExecutor {
    func execute(code: String, language: String, timeoutSeconds: Int) async -> NexusShellResult {
        NexusShellResult(ok: false, stdout: "", stderr: "iOS 本机 Linux 运行时未连接；当前设备不能执行 \(language) Shell。请改用云端 Container，或连接受审计的主人运行时。", exitCode: -1)
    }
}

@MainActor
final class NexusDeviceBridge: ObservableObject {
    enum State: Equatable { case offline, connecting, ready, failed(String) }

    @Published private(set) var state: State = .offline
    private var socket: URLSessionWebSocketTask?
    private let executor: any NexusShellExecutor
    private var pingTask: Task<Void, Never>?

    init(executor: any NexusShellExecutor = UnavailableNexusShellExecutor()) {
        self.executor = executor
    }

    func connect(baseURL: String) async {
        disconnect()
        state = .connecting
        do {
            let client = try NexusClient(base: baseURL)
            let url = try await client.webSocketURL()
            let task = URLSession.shared.webSocketTask(with: url)
            socket = task
            task.resume()
            try await send(["type": "device_shell_register", "platform": "ios", "runtime": "unavailable-until-connected"])
            receiveLoop()
            startPing()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        if case .failed = state {} else { state = .offline }
    }

    private func receiveLoop() {
        guard let socket else { return }
        Task { [weak self] in
            do {
                while true {
                    let message = try await socket.receive()
                    let text: String
                    switch message {
                    case .string(let value): text = value
                    case .data(let value): text = String(decoding: value, as: UTF8.self)
                    @unknown default: continue
                    }
                    await self?.handle(text)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .failed("设备桥接断开：\(error.localizedDescription)")
                }
            }
        }
    }

    private func handle(_ raw: String) async {
        guard let data = raw.data(using: .utf8), let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = frame["type"] as? String else { return }
        if type == "device_shell_ready" { state = .ready; return }
        guard type == "shell_exec", let id = frame["id"] as? String else { return }
        let code = frame["code"] as? String ?? ""
        let language = frame["lang"] as? String ?? "bash"
        let timeout = min(45, max(1, frame["timeout"] as? Int ?? 30))
        let result = await executor.execute(code: code, language: language, timeoutSeconds: timeout)
        try? await send([
            "type": "shell_result", "id": id, "ok": result.ok,
            "stdout": String(result.stdout.prefix(8000)), "stderr": String(result.stderr.prefix(2000)),
            "exit_code": result.exitCode,
        ])
    }

    private func startPing() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                try? await self?.send(["type": "ping"])
            }
        }
    }

    private func send(_ frame: [String: Any]) async throws {
        guard let socket else { throw NexusClientError.badResponse }
        let data = try JSONSerialization.data(withJSONObject: frame)
        try await socket.send(.data(data))
    }
}
