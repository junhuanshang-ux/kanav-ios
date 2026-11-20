import SafariServices
import UIKit
import WebKit

/// 整站壳：把站点当作原生 App 呈现。
/// 想换站点，只改 `Site.home` 与 `Site.trustedHostSuffixes` 即可。
final class WebViewController: UIViewController {

    // MARK: - 站点配置

    private enum Site {
        static let home = "https://kanav.ad/"
        /// 视为“站内”的域名后缀，站外链接自动用系统浏览器打开（挡掉广告跳转）
        static let trustedHostSuffixes = ["kanav.ad", "kanav.fun"]
        static let displayName = "KanAV"
        static let accent = UIColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1)
    }

    // MARK: - UI

    private var webView: WKWebView!
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let errorContainer = UIStackView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private lazy var backButton = UIBarButtonItem(
        image: UIImage(systemName: "chevron.backward"),
        style: .plain, target: self, action: #selector(handleBack))
    private lazy var forwardButton = UIBarButtonItem(
        image: UIImage(systemName: "chevron.forward"),
        style: .plain, target: self, action: #selector(handleForward))
    private lazy var homeButton = UIBarButtonItem(
        image: UIImage(systemName: "house"),
        style: .plain, target: self, action: #selector(loadHome))
    private lazy var reloadButton = UIBarButtonItem(
        image: UIImage(systemName: "arrow.clockwise"),
        style: .plain, target: self, action: #selector(handleReload))
    private lazy var shareButton = UIBarButtonItem(
        image: UIImage(systemName: "safari"),
        style: .plain, target: self, action: #selector(openInSystemBrowser))

    private var observations: [NSKeyValueObservation] = []

    // MARK: - 生命周期

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.title = Site.displayName
        setupWebView()
        setupChrome()
        setupErrorView()
        setupObservers()
        loadHome()
    }

    deinit {
        observations.forEach { $0.invalidate() }
    }

    // MARK: - 构建

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // 关闭“无手势也能 window.open”，从源头上少掉一半广告弹窗
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        // 伪装成 iOS Safari，避免站点把 WKWebView 识别成精简版甚至拒绝服务
        configuration.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        if #available(iOS 15.4, *) {
            // 允许 <video> 进入系统全屏播放器
            configuration.preferences.isElementFullscreenEnabled = true
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.underPageBackgroundColor = .black
        webView.translatesAutoresizingMaskIntoConstraints = false

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupChrome() {
        navigationItem.rightBarButtonItem = shareButton
        navigationItem.backButtonDisplayMode = .minimal

        backButton.isEnabled = false
        forwardButton.isEnabled = false
        homeButton.isEnabled = true
        shareButton.isEnabled = true

        toolbarItems = [
            backButton,
            UIBarButtonItem(systemItem: .flexibleSpace),
            forwardButton,
            UIBarButtonItem(systemItem: .flexibleSpace),
            homeButton,
            UIBarButtonItem(systemItem: .flexibleSpace),
            reloadButton
        ]

        progressView.progressTintColor = Site.accent
        progressView.trackTintColor = .clear
        progressView.alpha = 0
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    private func setupErrorView() {
        errorContainer.axis = .vertical
        errorContainer.alignment = .center
        errorContainer.spacing = 18
        errorContainer.isHidden = true
        errorContainer.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.textColor = UIColor(white: 0.85, alpha: 1)
        errorLabel.font = .systemFont(ofSize: 15, weight: .regular)
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center

        retryButton.setTitle("重新加载", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        retryButton.backgroundColor = Site.accent
        retryButton.layer.cornerRadius = 10
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 168).isActive = true
        retryButton.addTarget(self, action: #selector(handleReload), for: .touchUpInside)

        errorContainer.addArrangedSubview(errorLabel)
        errorContainer.addArrangedSubview(retryButton)
        view.addSubview(errorContainer)

        NSLayoutConstraint.activate([
            errorContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func setupObservers() {
        observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.performOnMain {
                let progress = Float(webView.estimatedProgress)
                self.progressView.setProgress(progress, animated: true)
                self.progressView.alpha = progress >= 1.0 ? 0 : 1
                if progress >= 1.0 {
                    self.activityIndicator.stopAnimating()
                }
            }
        })

        observations.append(webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.performOnMain {
                let title = webView.title ?? ""
                self.navigationItem.title = title.isEmpty ? Site.displayName : title
            }
        })

        observations.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.performOnMain { self.backButton.isEnabled = webView.canGoBack }
        })

        observations.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.performOnMain { self.forwardButton.isEnabled = webView.canGoForward }
        })
    }

    // MARK: - 动作

    @objc private func loadHome() {
        hideError()
        activityIndicator.startAnimating()
        var request = URLRequest(url: URL(string: Site.home)!)
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 40
        webView.load(request)
    }

    @objc private func handleBack() {
        if webView.canGoBack {
            webView.goBack()
        } else {
            let scrollView = webView.scrollView
            let top = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
            scrollView.setContentOffset(top, animated: true)
        }
    }

    @objc private func handleForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    @objc private func handleReload() {
        if webView.isLoading {
            webView.stopLoading()
        } else {
            hideError()
            webView.reload()
        }
    }

    @objc private func handlePullToRefresh() {
        hideError()
        webView.reload()
    }

    @objc private func openInSystemBrowser() {
        guard let url = webView.url else { return }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = Site.accent
        present(safari, animated: true)
    }

    // MARK: - 辅助

    private func performOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func refreshReloadIcon() {
        let symbol = webView.isLoading ? "xmark" : "arrow.clockwise"
        reloadButton.image = UIImage(systemName: symbol)
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorContainer.isHidden = false
        view.bringSubviewToFront(errorContainer)
        activityIndicator.stopAnimating()
    }

    private func hideError() {
        errorContainer.isHidden = true
    }

    private func isTrusted(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return Site.trustedHostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix("." + suffix)
        }
    }

    private func openExternally(_ url: URL) {
        guard UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        hideError()
        refreshReloadIcon()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.refreshControl?.endRefreshing()
        activityIndicator.stopAnimating()
        refreshReloadIcon()
        hideError()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(with: error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        finishLoading(with: error)
    }

    private func finishLoading(with error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        activityIndicator.stopAnimating()
        refreshReloadIcon()

        let nsError = error as NSError
        // 主动取消、重定向中断等不算失败
        guard nsError.code != NSURLErrorCancelled else { return }
        showError("加载失败\n\(nsError.localizedDescription)\n\n下拉刷新或点“重新加载”重试")
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = (url.scheme ?? "").lowercased()

        // 内联页面 / JS 伪协议：放行
        if ["about", "blob", "data", "javascript", "file"].contains(scheme) {
            decisionHandler(.allow)
            return
        }

        // 非 http(s)：itms-apps / mailto / tel / 自定义 scheme 交给系统
        if scheme != "http" && scheme != "https" {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }

        // 需要下载的文件（m3u8、mp4、zip…）交给系统处理
        if navigationAction.shouldPerformDownload {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }

        // target=_blank / window.open：站内继续在壳里打开，站外只在用户真的点了才丢给系统
        if navigationAction.targetFrame == nil {
            let userInitiated = navigationAction.navigationType == .linkActivated
                || navigationAction.navigationType == .formSubmitted
            if isTrusted(url) {
                webView.load(navigationAction.request)
            } else if userInitiated {
                openExternally(url)
            }
            // 剩下的当作广告弹窗，静默丢弃
            decisionHandler(.cancel)
            return
        }

        // 主框架上的外域跳转基本是广告，直接踢到系统浏览器
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        if isMainFrame, navigationAction.navigationType == .linkActivated, !isTrusted(url) {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {

        if !navigationResponse.canShowMIMEType, let url = navigationResponse.response.url {
            openExternally(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension WebViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {

        // 新窗口请求基本来自广告（popunder / window.open）
        if let url = navigationAction.request.url {
            let userInitiated = navigationAction.navigationType == .linkActivated
                || navigationAction.navigationType == .formSubmitted
            if isTrusted(url) {
                webView.load(navigationAction.request)
            } else if userInitiated {
                openExternally(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {

        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {

        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {

        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
}
