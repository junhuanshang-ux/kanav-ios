import Foundation
import UIKit
import WebKit

/// jable.tv 挂在 Cloudflare Turnstile 后面，URLSession 拿不到任何页面
/// （没有 JS 执行环境，必然停在 "Just a moment"）。
///
/// 这里用一个不可见的 WKWebView 当传输层：
///   1. 加载目标页 → 真实 WebKit 环境，Turnstile 多数情况自动放行
///   2. 通过后取 `document.documentElement.outerHTML` 交给解析器
///   3. cookie 同步进 HTTPCookieStorage，AVPlayer 拉 m3u8 时也能带上
///
/// 超时仍未通过就把 `needsManualCheck` 置 true，界面把 WebView 露出来让用户点一下；
/// 通过后 cf_clearance 会随 WKWebsiteDataStore 持久化，之后不再打扰。
final class WebFetcher: NSObject, ObservableObject {

    static let shared = WebFetcher()

    enum ProbeState: Equatable {
        case idle
        case verifying
        case ready
        case failed(String)
    }

    @Published private(set) var state: ProbeState = .idle
    @Published private(set) var needsManualCheck = false
    @Published private(set) var lastHTML: String = ""

    private var webView: WKWebView?
    private var isBusy = false
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private var queue: [URL] = []

    var manualWebView: WKWebView? { webView }

    // MARK: 对外

    /// 抓页面 HTML。并发调用自动排队，共用一个 WebView。
    func html(_ url: URL, timeout: Double = 28) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
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
        needsManualCheck = false
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

        polling(deadline: Date().addingTimeInterval(28), manualGranted: false, attempt: 0)
    }

    private func polling(deadline: Date, manualGranted: Bool, attempt: Int) {
        guard isBusy, let webView = webView else { return }

        webView.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
            guard self.isBusy else { return }
            let html = (result as? String) ?? ""

            if !Self.looksLikeChallenge(html), html.count > 2000 {
                self.finish(html)
                return
            }

            if Date() > deadline {
                if !manualGranted {
                    // 可能要求点一下 Turnstile：把 WebView 显示出来，再给 40 秒
                    self.needsManualCheck = true
                    self.polling(deadline: Date().addingTimeInterval(40), manualGranted: true, attempt: attempt + 1)
                } else {
                    self.finish(nil)
                }
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.polling(deadline: deadline, manualGranted: manualGranted, attempt: attempt + 1)
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

    // MARK: WebView

    private func prepareWebView() {
        guard webView == nil else { return }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"

        let view = WKWebView(frame: CGRect(x: -4, y: -4, width: 2, height: 2), configuration: config)
        view.customUserAgent = Site.userAgent
        view.isOpaque = false
        view.backgroundColor = .clear

        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let window = scene.keyWindow {
            window.addSubview(view)
        }
        webView = view
    }

    private func syncCookies() {
        webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
        }
    }
}
