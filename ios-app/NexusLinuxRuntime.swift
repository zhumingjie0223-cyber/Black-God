import Foundation

struct NexusLinuxResult {
    let output: String
    let errorOutput: String
    let exitCode: Int
    let duration: TimeInterval
    let failure: String?
    var succeeded: Bool { failure == nil && exitCode == 0 }
}

/// A single kernel per app. Commands are serialized; host app data is never mounted.
@MainActor
final class NexusLinuxRuntime {
    static let shared = NexusLinuxRuntime()
    private var busy = false
    var isExecuting: Bool { busy }
    private var preparedWorkspaces = Set<UUID>()
    private(set) var ready = false
    private var activePID: Int32?
    private var activeID: UUID?
    private var cancellationReason: String?
    private let rootParent: URL
    private lazy var journal = NexusExecutionJournal(url: rootParent.appendingPathComponent("execution-journal.json"))
    private(set) var interruptedCount = 0
    init(rootParent: URL? = nil) {
        self.rootParent = rootParent ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlackGodLinux", isDirectory: true)
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
    func execute(command: String, timeout: TimeInterval = 30, workspace: UUID = UUID(), onOutput: ((String, Bool) -> Void)? = nil) async throws -> NexusLinuxResult {
        try Task.checkCancellation()
        guard !busy else { throw NexusReasoningError.execution("Linux 正在执行另一项任务，请稍后重试。") }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !command.utf8.contains(0), command.utf8.count <= 32768,
              timeout.isFinite, timeout > 0, timeout <= 120 else {
            throw NexusReasoningError.execution("命令为空、过长或超时范围无效（1—120秒）。")
        }
        try prepare()
        guard ISHKernel.shared.reapAndCountGuestProcesses() == 0 else {
            throw NexusReasoningError.execution("上一次 Linux 进程尚未退出，请稍后重试或重启应用。")
        }
        busy = true
        defer { busy = false; ISHKernel.shared.nextRoot = nil }
        let storageRoot = rootParent
        let initialBudget = NexusStorage.budget()
        let measured = try await Task.detached(priority: .utility) { try NexusStorage.measureCached(root: storageRoot, budget: initialBudget) }.value
        let spaceBudget = NexusStorage.adoptExistingUsage(measured)
        let space = NexusStorageSnapshot(used: measured.used, free: measured.free, budget: spaceBudget, files: measured.files)
        blackgod_set_guest_storage(UInt64(space.budget), UInt64(max(0, space.used)))
        if let reason = space.stopReason { busy = false; throw NexusReasoningError.execution(reason) }
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                    let usage = try await Task.detached(priority: .utility) { try NexusStorage.measureCached(root: storageRoot, budget: spaceBudget) }.value
                    try Task.checkCancellation()
                    blackgod_set_guest_storage(UInt64(spaceBudget), UInt64(max(0, usage.used)))
                    if let reason = usage.stopReason { self.cancelActive(reason: reason); return }
                } catch is CancellationError { return }
                catch { self.cancelActive(reason: "空间检查失败，命令已停止"); return }
            }
        }
        defer { watcher.cancel() }
        let recordID = try journal.begin(workspace: workspace, command: command)
        do {
        let root = "/sessions/" + workspace.uuidString
        if !preparedWorkspaces.contains(workspace) {
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
        ISHKernel.shared.nextRoot = root
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
        guard let pid = activePID else { return }
        cancellationReason = reason
        print("LINUX_CANCEL reason=\(reason) pid=\(pid)")
        ISHShellExecutor.killProcessGroup(pid)
        ISHShellExecutor.finalizeTimedOutPid(pid)
    }
    var diagnostics: String { ISHShellExecutor.leakGuardStatus() }
}
