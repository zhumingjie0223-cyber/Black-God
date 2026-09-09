import SwiftUI
import SafariServices

struct NexusOAuthBrowser: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class NexusOAuthLogin: ObservableObject {
    @Published var browser: NexusOAuthBrowser?
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    @Published private(set) var completedEntry: NexusModelEntry?
    @Published private(set) var userCode: String?
    private var deviceBrowserURL: URL?
    private let deviceOAuth: NexusDeviceOAuth
    private var task: Task<Void, Never>?
    private var receiver: NexusOAuthCallback?
    private var generation = UUID()
    private var awaitingBrowser = false
    private let keychain: NexusKeychain
    private let exchange: (NexusOAuthAttempt, String) async throws -> String
    init(keychain: NexusKeychain = .shared, deviceOAuth: NexusDeviceOAuth = NexusDeviceOAuth(),
         exchange: @escaping (NexusOAuthAttempt, String) async throws -> String = { try await NexusOAuthExchange().exchange($0, code: $1) }) {
        self.keychain = keychain; self.exchange = exchange; self.deviceOAuth = deviceOAuth
    }
    func start(entry: NexusModelEntry) {
        guard !isRunning, NexusOAuthProvider.supports(entry) else { return }
        let id = UUID(); generation = id; completedEntry = nil
        isRunning = true; status = "正在打开官方授权页面…"
        task = Task {
            defer {
                if generation == id {
                    receiver?.cancel(); receiver = nil; awaitingBrowser = false
                    browser = nil; task = nil; isRunning = false
                }
            }
            do {
                let attempt = try NexusOAuthAttempt()
                let callback = NexusOAuthCallback(attempt: attempt); receiver = callback
                let port = try await callback.start()
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                awaitingBrowser = true
                browser = NexusOAuthBrowser(url: attempt.authorizationURL(port: port))
                status = "请在 OpenRouter 官方页面登录并同意授权。"
                let code = try await callback.waitForCode()
                try Task.checkCancellation()
                awaitingBrowser = false; browser = nil
                status = "授权已返回，正在保存连接…"
                let key = try await exchange(attempt, code)
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                // Save before exposing success. Model selection is a separate user decision.
                try keychain.saveOAuthDraft(entry, credential: key)
                completedEntry = entry
                status = "OAuth 登录成功，凭据已保存。请选择模型后使用。"
            } catch {
                guard generation == id else { return }
                status = Task.isCancelled || error is CancellationError ? "已取消登录。" : error.localizedDescription
            }
        }
    }
    func startDevice(_ provider: NexusDeviceProvider, entry: NexusModelEntry? = nil) {
        guard !isRunning else { return }
        let target = entry ?? provider.entry()
        guard provider.matches(target) else { return }
        let id = UUID(); generation = id; completedEntry = nil
        isRunning = true; status = "正在获取设备授权…"
        task = Task {
            defer {
                if generation == id {
                    deviceBrowserURL = nil; userCode = nil; browser = nil; task = nil; isRunning = false
                }
            }
            do {
                let proof = try NexusOAuthAttempt()
                let auth = try await deviceOAuth.begin(provider, proof: proof)
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                userCode = auth.userCode; deviceBrowserURL = auth.browserURL
                browser = NexusOAuthBrowser(url: auth.browserURL)
                status = "请在服务商页面完成授权。关闭页面后会继续等待；可点击取消停止。"
                let credential = try await deviceOAuth.poll(provider, auth: auth, proof: proof, sessionID: UUID().uuidString)
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                completedEntry = try keychain.saveDeviceOAuthDraft(target, credential: credential)
                status = "账号授权已保存。请选择模型并测试账号的调用权限。"
            } catch {
                guard generation == id else { return }
                status = Task.isCancelled || error is CancellationError ? "已取消登录。" : "账号授权未完成：" + (error as? NexusOAuthError ?? .invalidResponse).localizedDescription
            }
        }
    }
    func reopenBrowser() {
        if isRunning, let url = deviceBrowserURL { browser = NexusOAuthBrowser(url: url) }
    }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil; receiver?.cancel(); receiver = nil
        awaitingBrowser = false; deviceBrowserURL = nil; userCode = nil; browser = nil; isRunning = false; status = "已取消登录。"
    }
    func browserDismissed() {
        browser = nil
        if awaitingBrowser { cancel() }
    }
}

/// UIKit owns only the Safari modal, so dismissing it cannot dismiss SwiftUI's
/// enclosing connection sheet as well. Its lifetime still follows the login state.
struct NexusOAuthSafariPresenter: UIViewControllerRepresentable {
    let browser: NexusOAuthBrowser?
    let onCancel: () -> Void
    func makeUIViewController(context: Context) -> NexusOAuthPresenterController { NexusOAuthPresenterController() }
    func updateUIViewController(_ controller: NexusOAuthPresenterController, context: Context) {
        controller.browser = browser; controller.onCancel = onCancel; controller.synchronize()
    }
    static func dismantleUIViewController(_ controller: NexusOAuthPresenterController, coordinator: ()) {
        controller.browser = nil; controller.synchronize()
    }
}

final class NexusOAuthPresenterController: UIViewController, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    var browser: NexusOAuthBrowser?
    var onCancel: (() -> Void)?
    private weak var safari: SFSafariViewController?
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); synchronize() }
    func synchronize() {
        guard let browser else {
            if let current = safari { safari = nil; current.dismiss(animated: true) }
            return
        }
        guard safari == nil, viewIfLoaded?.window != nil else { return }
        let controller = SFSafariViewController(url: browser.url)
        controller.delegate = self; controller.modalPresentationStyle = .pageSheet
        safari = controller
        present(controller, animated: true)
        controller.presentationController?.delegate = self
    }
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        safari = nil
        controller.dismiss(animated: true)
        onCancel?()
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        safari = nil; onCancel?()
    }
}
