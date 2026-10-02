import Foundation

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

/// A single kernel per app. Commands are serialized; host app data is never mounted.
@MainActor
final class NexusLinuxRuntime {
    static let shared = NexusLinuxRuntime()
    private var busy = false
    private var executionToken: UUID?
    var isExecuting: Bool { busy }
    private var preparedWorkspaces = Set<UUID>()
    private(set) var ready = false
    private var activePID: Int32?
    private var activeID: UUID?
    private var cancellationReason: String?
    private var preparationTask: Task<NexusStorageSnapshot, Error>?
    private let measureStorage: (URL, Int64) async throws -> NexusStorageSnapshot
    private let rootParent: URL
    private lazy var journal = NexusExecutionJournal(url: rootParent.appendingPathComponent("execution-journal.json"))
    private(set) var interruptedCount = 0
    init(rootParent: URL? = nil, measureStorage: @escaping (URL, Int64) async throws -> NexusStorageSnapshot = { root, budget in
        try await NexusStorage.measureInBackground(root: root, budget: budget, useCache: true)
    }) {
        self.rootParent = rootParent ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlackGodLinux", isDirectory: true)
        self.measureStorage = measureStorage
    }
    func prepare() throws {
        if ready { return }
        interruptedCount = try journal.recoverInterrupted()
        let fm = FileManager.default
        guard let source = Bundle.main.url(forResource: "AlpineRootfs", withExtension: nil) else {
            throw NexusReasoningError.execution("缺少 Linux 文件系统，请重新构建运行环境。")
        }
        let root = try NexusRuntimeImage.install(source: source, parent: rootParent)
        var excluded = rootParent
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let code = ISHKernel.shared.boot(withRootPath: root.path)
        guard code == 0 else { throw NexusReasoningError.execution("Linux 启动失败（\(code)），请重启应用后再试。") }
        ready = true
    }
    func execute(command: String, timeout: TimeInterval = 30, workspace: UUID = UUID(), onStatus: ((String) -> Void)? = nil, onOutput: ((String, Bool) -> Void)? = nil) async throws -> NexusLinuxResult {
        try Task.checkCancellation()
        guard !busy else { throw NexusReasoningError.execution("Linux 正在执行另一项任务，请稍后重试。") }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !command.utf8.contains(0), command.utf8.count <= 32768,
              timeout.isFinite, timeout > 0, timeout <= 120 else {
            throw NexusReasoningError.execution("命令为空、过长或超时范围无效（1—120秒）。")
        }
        onStatus?("正在准备运行环境…")
        try prepare()
        guard ISHKernel.shared.reapAndCountGuestProcesses() == 0 else {
            throw NexusReasoningError.execution("上一次 Linux 进程尚未退出，请稍后重试或重启应用。")
        }
        busy = true
        let token = UUID()
        executionToken = token
        cancellationReason = nil
        defer {
            preparationTask?.cancel(); preparationTask = nil
            busy = false; executionToken = nil; cancellationReason = nil; ISHKernel.shared.nextRoot = nil
        }
        let storageRoot = rootParent
        let initialBudget = NexusStorage.budget()
        onStatus?("正在检查工作区与可用空间…")
        let scan = Task { try await measureStorage(storageRoot, initialBudget) }
        preparationTask = scan
        let measured: NexusStorageSnapshot
        do {
            measured = try await withTaskCancellationHandler {
                let snapshot = try await scan.value
                try Task.checkCancellation()
                return snapshot
            } onCancel: { scan.cancel() }
        } catch {
            try Task.checkCancellation()
            if let cancellationReason { throw NexusReasoningError.execution(cancellationReason) }
            throw error
        }
        preparationTask = nil
        try checkPreparationCancellation()
        let spaceBudget = NexusStorage.adoptExistingUsage(measured)
        let space = NexusStorageSnapshot(used: measured.used, free: measured.free, budget: spaceBudget, files: measured.files)
        blackgod_set_guest_storage(UInt64(space.budget), UInt64(max(0, space.used)))
        if let reason = space.stopReason { busy = false; throw NexusReasoningError.execution(reason) }
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                    let usage = try await self.measureStorage(storageRoot, spaceBudget)
                    try Task.checkCancellation()
                    guard self.executionToken == token else { return }
                    blackgod_set_guest_storage(UInt64(spaceBudget), UInt64(max(0, usage.used)))
                    if let reason = usage.stopReason { self.cancelActive(reason: reason); return }
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled, self.executionToken == token else { return }
                    self.cancelActive(reason: "空间检查失败，命令已停止"); return
                }
            }
        }
        defer { watcher.cancel() }
        let recordID = try journal.begin(workspace: workspace, command: command)
        do {
        let root = "/sessions/" + workspace.uuidString
        if !preparedWorkspaces.contains(workspace) {
            onStatus?("正在准备独立工作区…")
            let setup = """
            set -e
            if [ ! -d '\(root)' ] && [ -d '\(root).previous' ]; then mv '\(root).previous' '\(root)'; fi
            if [ ! -f '\(root)/.ready' ]; then
              mkdir -p /sessions
              chmod 700 /sessions
              staging='\(root).install'
              rm -rf "$staging"
              mkdir -p "$staging"
              cp -al /bin /sbin /lib /usr /etc "$staging/"
              mkdir -p "$staging/dev" "$staging/tmp" "$staging/workspace"
              cp -a /dev/null /dev/zero /dev/urandom "$staging/dev/"
              chown 1000:1000 "$staging/workspace" "$staging/tmp"
              chmod 700 "$staging/workspace" "$staging/tmp"
              if [ -d '\(root)/workspace' ]; then cp -a '\(root)/workspace/.' "$staging/workspace/"; fi
              touch "$staging/.ready"
              if [ -d '\(root)' ]; then rm -rf '\(root).previous'; mv '\(root)' '\(root).previous'; fi
              mv "$staging" '\(root)'
              rm -rf '\(root).previous'
            fi
            """
            ISHKernel.shared.nextRoot = nil
            let result = try await runCommand(command: setup, timeout: 30)
            guard result.succeeded else { throw NexusReasoningError.execution("无法创建独立工作区：" + (result.failure ?? result.errorOutput)) }
            preparedWorkspaces.insert(workspace)
        }
        try checkPreparationCancellation()
        ISHKernel.shared.nextRoot = root
        onStatus?("正在执行命令")
        let result = try await runCommand(command: "umask 077\ncd /workspace || exit 125\n" + command, timeout: timeout, onOutput: onOutput)
        // 被系统（进入后台、空间不足）强制停止的命令记为“意外中断”，用户主动停止记为“已取消”；只有命令自身出错才记“失败”。
        let status: String
        if result.succeeded { status = "completed" }
        else if result.exitCode < 0, let reason = cancellationReason { status = reason == "用户停止" ? "cancelled" : "interrupted" }
        else { status = "failed" }
        try journal.finish(recordID, status: status, exitCode: result.exitCode)
        return result
        } catch {
            try? journal.finish(recordID, status: Task.isCancelled ? "cancelled" : "failed")
            throw error
        }
    }
    func recentExecutions() throws -> [NexusExecutionRecord] { try journal.records() }

    /// 已安装镜像根目录（含 data/sessions）；未安装时为 nil。
    func installedImageRoot() -> URL? {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: rootParent, includingPropertiesForKeys: nil) else { return nil }
        return children.first { fm.fileExists(atPath: $0.appendingPathComponent("meta.db").path) }
    }

    func hostWorkspaceURL(for workspace: UUID) -> URL? {
        installedImageRoot()?.appendingPathComponent("data/sessions/\(workspace.uuidString)/workspace", isDirectory: true)
    }

    /// 列出沙箱工作区文件（相对 /workspace）。必要时先准备环境。
    func listWorkspaceFiles(workspace: UUID, limit: Int = 80) async throws -> [NexusWorkspaceFile] {
        let result = try await execute(
            command: "find . -maxdepth 3 \\( -type f -o -type l \\) ! -path './.*' 2>/dev/null | sed 's|^\\./||' | head -n \(max(1, limit))",
            timeout: 30,
            workspace: workspace
        )
        guard result.succeeded || !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let detail = result.failure ?? (result.errorOutput.isEmpty ? "无法列出工作区文件" : result.errorOutput)
            throw NexusReasoningError.execution(detail)
        }
        return result.output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("\0") && !$0.hasPrefix("../") }
            .prefix(limit)
            .map { NexusWorkspaceFile(path: $0) }
    }

    func importToWorkspace(data: Data, named name: String, workspace: UUID) async throws {
        let safe = Self.sanitizeFileName(name)
        guard !data.isEmpty, data.count <= 2 * 1024 * 1024 else {
            throw NexusReasoningError.execution("导入文件需在 1 字节到 2 MiB 之间。")
        }
        _ = try await execute(command: "true", timeout: 30, workspace: workspace)
        guard let dir = hostWorkspaceURL(for: workspace) else {
            throw NexusReasoningError.execution("工作区尚未就绪，请先打开沙箱或运行一条命令。")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent(safe)
        try data.write(to: target, options: .atomic)
    }

    func exportWorkspaceFile(_ path: String, workspace: UUID) async throws -> Data {
        let safe = Self.sanitizeRelativePath(path)
        let encoded = safe.replacingOccurrences(of: "'", with: "'\\''")
        let result = try await execute(
            command: "test -f '\(encoded)' && wc -c < '\(encoded)' && base64 '\(encoded)'",
            timeout: 60,
            workspace: workspace
        )
        guard result.succeeded else {
            throw NexusReasoningError.execution(result.failure ?? "无法导出该文件")
        }
        let lines = result.output.split(whereSeparator: \.isNewline).map(String.init)
        guard let sizeLine = lines.first, let size = Int(sizeLine.trimmingCharacters(in: .whitespaces)), size <= 2 * 1024 * 1024 else {
            throw NexusReasoningError.execution("文件过大或不存在（导出上限 2 MiB）。")
        }
        let b64 = lines.dropFirst().joined()
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
            throw NexusReasoningError.execution("导出解码失败。")
        }
        return data
    }

    func clearWorkspaceFiles(workspace: UUID, confirm: String) async throws {
        guard confirm.trimmingCharacters(in: .whitespacesAndNewlines) == "确认清空工作区" else {
            throw NexusReasoningError.execution("确认口令不正确。请输入「确认清空工作区」。")
        }
        let result = try await execute(command: "find . -mindepth 1 -maxdepth 3 -exec rm -rf {} + 2>/dev/null; printf cleared", timeout: 60, workspace: workspace)
        guard result.succeeded else { throw NexusReasoningError.execution(result.failure ?? "清空失败") }
    }

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

    private func checkPreparationCancellation() throws {
        try Task.checkCancellation()
        if let cancellationReason { throw NexusReasoningError.execution(cancellationReason) }
    }

    private func runCommand(command: String, timeout: TimeInterval, onOutput: ((String, Bool) -> Void)? = nil) async throws -> NexusLinuxResult {
        try Task.checkCancellation()
        let operationID = UUID()
        activeID = operationID
        cancellationReason = nil
        defer { activePID = nil; activeID = nil }
        let script = command + "\n"
        do {
        let value: NexusLinuxResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var finished = false
                var timer: Task<Void, Never>?
                func finish(_ result: Result<NexusLinuxResult, Error>) {
                    guard !finished else { return }
                    finished = true
                    timer?.cancel()
                    continuation.resume(with: result)
                }
                let pid = ISHShellExecutor.executeExecutable("/bin/sh", arguments: [], environment: [:], stdinData: Data(script.utf8), lineCallback: { line, isError in
                    guard !finished, self.activeID == operationID else { return }
                    onOutput?(line, isError)
                }) { result in
                    // ObjC completion is delivered on main queue.
                    let status = Int(result.exitCode)
                    let exit = status < 0 ? status : ((status & 127) == 0 ? (status >> 8) & 255 : 128 + (status & 127))
                    let failure = result.error.rawValue == 0 ? nil : self.cancellationReason ?? "Linux 执行失败（\(result.error.rawValue)）；可能已超时或超过输出上限。"
                    finish(.success(NexusLinuxResult(output: result.output, errorOutput: result.errorOutput,
                        exitCode: exit, duration: result.duration, failure: failure)))
                }
                guard pid > 1 else {
                    finish(.failure(NexusReasoningError.execution("无法启动 Linux 进程（\(pid)）。")))
                    return
                }
                self.activePID = pid
                timer = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    guard !finished else { return }
                    finish(.failure(NexusReasoningError.execution("Linux 命令超时，已终止进程组。")))
                    ISHShellExecutor.killProcessGroup(pid)
                    ISHShellExecutor.finalizeTimedOutPid(pid)
                }
                if Task.isCancelled {
                    finish(.failure(CancellationError()))
                    ISHShellExecutor.killProcessGroup(pid)
                    ISHShellExecutor.finalizeTimedOutPid(pid)
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard self.activeID == operationID else { return }
                self.cancelActive(reason: "任务取消")
            }
        }
        await cleanUp()
        try Task.checkCancellation()
        return value
        } catch {
            await cleanUp()
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }
    private func cleanUp() async {
        ISHKernel.shared.terminateGuestProcesses()
        // An independent task allows cleanup to finish even when the caller was cancelled.
        await Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(50))
                if ISHKernel.shared.reapAndCountGuestProcesses() == 0 { break }
            }
        }.value
    }
    func cancelActive(reason: String = "用户停止") {
        guard busy else { return }
        cancellationReason = reason
        preparationTask?.cancel()
        guard let pid = activePID else { return }
        print("LINUX_CANCEL reason=\(reason) pid=\(pid)")
        ISHShellExecutor.killProcessGroup(pid)
        ISHShellExecutor.finalizeTimedOutPid(pid)
    }
    var diagnostics: String { ISHShellExecutor.leakGuardStatus() }
}
