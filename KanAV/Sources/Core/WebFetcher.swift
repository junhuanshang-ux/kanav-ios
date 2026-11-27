import Foundation
import UIKit
import WebKit

/// jable.tv 挂在 Cloudflare Turnstile 后面，URLSession 拿不到任何页面。
/// 这里用一个 WKWebView 当传输层：加载 → 过验证 → 取 outerHTML → 解析。
///
/// 如果自动验证 28 秒没通过，会把这层 WebView **全屏弹出来**让用户手点
/// （Turnstile 有时要求交互），点完之后自动收起并继续抓取。
final class WebFetcher: NSObject, ObservableObject {

    static let shared = WebFetcher()

    enum ProbeState: Equatable {
        case idle
        case verifying
        case waitingUser
        case ready
        case failed(String)
    }

    @Published private(set) var state: ProbeState = .idle
    @Published private(set) var needsManualCheck = false
    @Published private(set) var lastHTML: String = ""

    private var webView: WKWebView?
    /// 长期承载 webView 的容器（后台时缩到 2×2）
    private var hostView: UIView?
    /// 手动验证时的全屏遮罩
    private var overlay: UIView?

    private var isBusy = false
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private var queue: [URL] = []

    var manualWebView: WKWebView? { webView }

    // MARK: 对外

    /// 播放页里不要弹手动验证（会盖住播放器），由调用方传 false
    private var manualCheckAllowed = true

    func html(_ url: URL, timeout: Double = 28, allowManualCheck: Bool = true) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.manualCheckAllowed = allowManualCheck
                self.queue.append(url)
                self.waiters.append(continuation)
                self.pump()
            }
        }
    }

    func cookieHeader(for url: URL) -> String? {
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        guard !cookies.isEmpty else { return nil }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    // MARK: 调度

    private func pump() {
        guard !isBusy, !queue.isEmpty else { return }
        isBusy = true
        state = .verifying
        lastHTML = ""

        let url = queue.removeFirst()
        load(url: url)
    }

    private func load(url: URL) {
        prepareWebView()
        guard let webView = webView else {
            finish(nil)
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Site.base + "/", forHTTPHeaderField: "Referer")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        webView.load(request)

        polling(deadline: Date().addingTimeInterval(28), manualPhase: 0, attempt: 0)
    }

    private func polling(deadline: Date, manualPhase: Int, attempt: Int) {
        guard isBusy, let webView = webView else { return }

        webView.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
            guard self.isBusy else { return }
            let html = (result as? String) ?? ""

            if !Self.looksLikeChallenge(html), html.count > 2000 {
                self.hideManualCheck()
                self.finish(html)
                return
            }

            if Date() > deadline {
                if !self.manualCheckAllowed {
                    self.finish(nil)
                    return
                }
                switch manualPhase {
                case 0:
                    // 自动验证没通过 → 弹出来让用户点
                    self.showManualCheck()
                    self.polling(deadline: Date().addingTimeInterval(120), manualPhase: 1, attempt: attempt + 1)
                case 1:
                    // 用户点了两分钟还没过
                    self.polling(deadline: Date().addingTimeInterval(120), manualPhase: 2, attempt: attempt + 1)
                default:
                    self.hideManualCheck()
                    self.finish(nil)
                }
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.polling(deadline: deadline, manualPhase: manualPhase, attempt: attempt + 1)
            }
        }
    }

    private func finish(_ html: String?) {
        guard isBusy else { return }
        isBusy = false

        if let html = html, !html.isEmpty {
            lastHTML = html
            state = .ready
            syncCookies()
        } else {
            state = .failed("页面没能加载出来")
        }
        needsManualCheck = false

        let waiter = waiters.isEmpty ? nil : waiters.removeFirst()
        waiter?.resume(returning: (html?.isEmpty == false) ? html : nil)
        pump()
    }

    static func looksLikeChallenge(_ html: String) -> Bool {
        if html.isEmpty { return true }
        let hints = ["Just a moment", "请稍候", "cf-challenge", "cf_chl_opt", "challenge-platform", "__cf_chl"]
        return hints.contains { html.contains($0) }
    }

    // MARK: WebView 装配

    private func prepareWebView() {
        guard webView == nil else { return }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"

        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = Site.userAgent

        let host = UIView(frame: CGRect(x: -4, y: -4, width: 2, height: 2))
        host.clipsToBounds = true
        host.addSubview(view)
        view.frame = host.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if let window = keyWindow {
            window.addSubview(host)
        }
        hostView = host
        webView = view
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow
    }

    private func syncCookies() {
        webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
        }
    }

    // MARK: 手动验证界面

    func showManualCheck() {
        guard let window = keyWindow, let host = hostView else { return }
        needsManualCheck = true
        state = .waitingUser

        if overlay == nil {
            buildOverlay(in: window)
        }
        guard let container = overlay else { return }

        host.removeFromSuperview()
        host.frame = container.bounds
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(host)
        host.isUserInteractionEnabled = true

        container.isHidden = false
        window.bringSubviewToFront(container)
        window.endEditing(true)
    }

    private func buildOverlay(in window: UIWindow) {
        let container = UIView(frame: window.bounds)
        container.backgroundColor = .black
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.isHidden = true

        let barHeight: CGFloat = 92
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: window.bounds.width, height: barHeight))
        bar.backgroundColor = UIColor(white: 0.08, alpha: 0.98)
        bar.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]

        let title = UILabel()
        title.text = "站点要求人机验证"
        title.textColor = .white
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let subtitle = UILabel()
        subtitle.text = "在下方完成验证后会自动继续"
        subtitle.textColor = UIColor(white: 0.6, alpha: 1)
        subtitle.font = .systemFont(ofSize: 12)

        let close = UIButton(type: .system)
        close.setTitle("关闭", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        close.backgroundColor = UIColor.systemPink
        close.layer.cornerRadius = 14
        close.frame = CGRect(x: window.bounds.width - 78, y: barHeight - 46, width: 62, height: 30)
        close.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
        close.addTarget(self, action: #selector(handleCloseTapped), for: .touchUpInside)

        title.frame = CGRect(x: 16, y: 40, width: window.bounds.width - 110, height: 22)
        title.autoresizingMask = [.flexibleWidth]
        subtitle.frame = CGRect(x: 16, y: 64, width: window.bounds.width - 110, height: 18)
        subtitle.autoresizingMask = [.flexibleWidth]

        bar.addSubview(title)
        bar.addSubview(subtitle)
        bar.addSubview(close)
        container.addSubview(bar)

        // 给 webView 容器留出顶部栏空间
        webHostContainerTopInset = barHeight

        window.addSubview(container)
        overlay = container
    }

    private var webHostContainerTopInset: CGFloat = 0

    @objc private func handleCloseTapped() {
        hideManualCheck()
        if isBusy {
            finish(nil)
        }
    }

    func hideManualCheck() {
        needsManualCheck = false
        if state == .waitingUser {
            state = .verifying
        }

        guard let window = keyWindow, let host = hostView else {
            overlay?.isHidden = true
            return
        }

        host.removeFromSuperview()
        host.frame = CGRect(x: -4, y: -4, width: 2, height: 2)
        host.autoresizingMask = []
        window.addSubview(host)
        host.isUserInteractionEnabled = false

        overlay?.isHidden = true
    }
}
