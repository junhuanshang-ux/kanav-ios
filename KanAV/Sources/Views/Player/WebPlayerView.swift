import AVKit
import SwiftUI
import WebKit

/// 网页播放器：直接加载 jable 的视频页，用站点自带的播放器。
///
/// 为什么这是最优解：
///   - Cloudflare cookie、Referer、UA 全部是这个 WebView 自己产出的，天然一致
///   - 站点的 m3u8 / 分片鉴权、master playlist、iframe 播放器全部由页面自己处理
///   - 原生 AVPlayer 再怎么补 header 也是二等公民，CDN 一限速就废
/// 代价是播放控件是网页的（jable 自带的那套其实很完整：进度、音量、清晰度、全屏都有）。
struct WebPlayerView: View {

    let item: VideoItem

    @StateObject private var controller = WebPlayerController()
    @State private var controlsVisible = true
    @State private var hideWork: DispatchWorkItem?

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            WebPlayerSurface(webView: controller.webView)
                .ignoresSafeArea()

            if controller.isLoading {
                loadingOverlay
            }

            if let message = controller.errorText {
                failureOverlay(message)
            }

            if controlsVisible {
                topBar
                    .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            OrientationSupport.restoreDefault()
            OrientationSupport.setTabBarHidden(true)
            HistoryStore.shared.record(item)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            controller.stop()
            OrientationSupport.restoreDefault()
            OrientationSupport.setTabBarHidden(false)
        }
        .task {
            controller.load(Site.url(item.playPath))
            scheduleHide()
        }
    }

    // MARK: 顶部栏

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 2)

                Spacer(minLength: 4)

                Button {
                    controller.reload()
                    showControls()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            Spacer()

            // 点击后隐藏面板的热区
            Color.clear
                .frame(height: 0)
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("正在打开播放页…")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(20)
        .background(Color.black.opacity(0.45))
        .cornerRadius(12)
        .allowsHitTesting(false)
    }

    private func failureOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.gray)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            HStack(spacing: 12) {
                Button("重试") {
                    controller.reload()
                    showControls()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.kanAccent))

                Button("返回") {
                    presentationMode.wrappedValue.dismiss()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.14)))
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.75))
        .cornerRadius(14)
    }

    private func showControls() {
        controlsVisible = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem {
            controlsVisible = false
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }
}

// MARK: - WKWebView 容器

struct WebPlayerSurface: UIViewRepresentable {

    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - 控制器

final class WebPlayerController: NSObject, ObservableObject {

    let webView: WKWebView

    @Published private(set) var isLoading = true
    @Published private(set) var errorText: String?
    @Published private(set) var progress: Double = 0

    private var progressObservation: NSKeyValueObservation?
    private var targetURL: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        // 复用 WebFetcher 的 data store：CF 过验证后的 cookie 直接可用
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.customUserAgent = Site.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.scrollView.backgroundColor = .black

        if #available(iOS 15.4, *) {
            webView.configuration.preferences.isElementFullscreenEnabled = true
        }

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            let value = webView.estimatedProgress
            DispatchQueue.main.async { self?.progress = value }
        }
    }

    deinit {
        progressObservation?.invalidate()
    }

    func load(_ url: URL) {
        targetURL = url
        errorText = nil
        isLoading = true

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Site.base + "/", forHTTPHeaderField: "Referer")
        webView.load(request)
    }

    func reload() {
        if let url = targetURL {
            load(url)
        } else {
            webView.reload()
        }
    }

    func stop() {
        webView.stopLoading()
        webView.loadHTMLString("<html><body style='background:#000'></body></html>", baseURL: nil)
    }
}

extension WebPlayerController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorText = "播放页加载失败（\(nsError.code)）"
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorText = "播放页加载失败（\(nsError.code)）"
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "http" && scheme != "https" && scheme != "about" && scheme != "blob" && scheme != "data" {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        // 站内新窗口（如切清晰度）就地打开
        if navigationAction.targetFrame == nil, url.host?.contains("jable") == true {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

extension WebPlayerController: WKUIDelegate {

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           url.host?.contains("jable") == true {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
