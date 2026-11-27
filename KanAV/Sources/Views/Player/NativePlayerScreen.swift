import AVFoundation
import SwiftUI

/// 原生播放器：AVPlayerLayer + 自绘控件。
struct NativePlayerScreen: View {

    let item: VideoItem
    var onStateChange: ((PlaybackState) -> Void)?
    var onProgress: ((Double, Double) -> Void)?

    @StateObject private var engine = PlayerEngine()
    @ObservedObject private var favorites = FavoritesStore.shared

    @State private var activeItem: VideoItem
    @State private var isFullscreen = false
    @State private var controlsVisible = true
    @State private var hud: PlayerHUDKind?
    @State private var isResolving = true
    @State private var resolveError: String?
    @State private var streamURL: URL?
    @State private var recommendations: [VideoItem] = []
    @State private var hideWork: DispatchWorkItem?

    @Environment(\.presentationMode) private var presentationMode

    init(
        item: VideoItem,
        onStateChange: ((PlaybackState) -> Void)? = nil,
        onProgress: ((Double, Double) -> Void)? = nil
    ) {
        self.item = item
        self.onStateChange = onStateChange
        self.onProgress = onProgress
        _activeItem = State(initialValue: item)
    }

    private var isFavorite: Bool {
        favorites.contains(activeItem)
    }

    // MARK: Body

    var body: some View {
        content
            .navigationBarHidden(isFullscreen)
            .statusBar(hidden: isFullscreen)
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
            .task {
                await resolve(activeItem)
            }
            .onChange(of: engine.state) { newState in
                onStateChange?(newState)
                if newState.isPlaying {
                    scheduleHideControls()
                }
            }
    }

    private var content: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    playerArea(width: proxy.size.width)
                    if !isFullscreen {
                        embeddedInfo
                    }
                }
            }
        }
    }

    // MARK: 播放器区域

    private func playerArea(width: CGFloat) -> some View {
        baseLayer
            .frame(width: width, height: isFullscreen ? nil : width * 9.0 / 16.0)
            .frame(maxHeight: isFullscreen ? .infinity : nil)
            .overlay(hudOverlay)
            .overlay(controlsOverlay)
            .background(Color.black)
    }

    private var baseLayer: some View {
        ZStack {
            PlayerSurface(player: engine.player, gravity: engine.gravity) { _ in }
                .ignoresSafeArea(.all, edges: isFullscreen ? .all : [])
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }

            PlayerGestureLayer(engine: engine, hud: $hud) {
                toggleControls()
            }

            if isResolving {
                loadingOverlay
            } else if let message = resolveError {
                failureOverlay(message)
            } else if engine.state.isBusy {
                bufferingBadge
            }
        }
    }

    @ViewBuilder private var hudOverlay: some View {
        if let hud = hud {
            PlayerHUDView(hud: hud)
        }
    }

    @ViewBuilder private var controlsOverlay: some View {
        if !isResolving, resolveError == nil {
            PlayerControls(
                engine: engine,
                title: activeItem.title,
                isFullscreen: isFullscreen,
                onBack: handleBack,
                onToggleFullscreen: toggleFullscreen
            )
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("正在解析播放地址…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private func failureOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundColor(.gray)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                HStack(spacing: 12) {
                    Button("重试") {
                        Task { await resolve(activeItem) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.kanAccent))

                    Button("返回") {
                        handleBack()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                }
            }
        }
    }

    private var bufferingBadge: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                ProgressView().tint(.white).scaleEffect(0.8)
                Text("缓冲中")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.55))
            .cornerRadius(12)
            .padding(.bottom, isFullscreen ? 70 : 12)
        }
        .allowsHitTesting(false)
    }

    // MARK: 内嵌信息区

    private var embeddedInfo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleRow

                if !recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("猜你喜欢")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.kanTextPrimary)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 16
                        ) {
                            ForEach(recommendations) { entry in
                                Button {
                                    play(entry)
                                } label: {
                                    VideoCard(item: entry)
                                }
                                .buttonStyle(CardButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.kanBackground)
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                if let code = activeItem.code {
                    Text(code)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.kanAccent)
                }
                Text(activeItem.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.kanTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(activeItem.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color.kanTextSecondary)
            }

            Spacer(minLength: 0)

            Button {
                FavoritesStore.shared.toggle(activeItem)
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isFavorite ? Color.kanAccent : Color.kanTextSecondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.kanSurface))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 动作

    private func handleAppear() {
        UIApplication.shared.isIdleTimerDisabled = true
        OrientationSupport.restoreDefault()
        OrientationSupport.setTabBarHidden(true)
        HistoryStore.shared.record(activeItem)

        engine.onProgress = { current, duration in
            onProgress?(current, duration)
        }
    }

    private func handleDisappear() {
        engine.unload()
        hideWork?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        OrientationSupport.restoreDefault()
        OrientationSupport.setTabBarHidden(false)
    }

    private func play(_ next: VideoItem) {
        guard next.id != activeItem.id else { return }
        activeItem = next
        HistoryStore.shared.record(next)
        showControls()
        Task { await resolve(next) }
    }

    private func resolve(_ target: VideoItem) async {
        isResolving = true
        resolveError = nil

        if let cached = PlayURLCache.shared.get(target.id) {
            streamURL = cached.url
            engine.load(url: cached.url, referer: cached.referer, autoplay: true)
            isResolving = false
            showControls()
            return
        }

        do {
            let pageURL = Site.url(target.playPath)
            var html = try await Net.html(path: target.playPath, allowManualCheck: false)

            // 播放页里同时有「猜你喜欢」，先解析出来
            recommendations = Parser.videos(in: html).filter { $0.id != target.id }

            var source = Parser.playSource(from: html, fallbackTitle: target.title)

            if source == nil, let inner = Parser.iframeSource(in: html) {
                if let innerHTML = try? await Net.html(path: inner.absoluteString, allowManualCheck: false) {
                    source = Parser.playSource(from: innerHTML, fallbackTitle: target.title)
                }
            }

            guard let found = source else { throw KanError.noPlayURL }

            let resolved = try await StreamResolver.resolve(found.url, referer: pageURL.absoluteString)
            PlayURLCache.shared.set(target.id, url: resolved.url, referer: resolved.referer)

            streamURL = resolved.url
            engine.load(
                url: resolved.url,
                referer: resolved.referer,
                userAgent: resolved.userAgent,
                autoplay: true
            )
            isResolving = false
            showControls()
        } catch let error {
            streamURL = nil
            resolveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isResolving = false
        }
    }

    private func toggleFullscreen() {
        isFullscreen.toggle()
        if isFullscreen {
            OrientationSupport.enterLandscape()
        } else {
            OrientationSupport.enterPortrait()
        }
        showControls()
    }

    private func handleBack() {
        if isFullscreen {
            toggleFullscreen()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible {
            scheduleHideControls()
        }
    }

    private func showControls() {
        controlsVisible = true
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideWork?.cancel()
        guard engine.state.isPlaying else { return }
        let work = DispatchWorkItem {
            controlsVisible = false
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }
}
