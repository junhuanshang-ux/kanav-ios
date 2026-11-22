import AVFoundation
import SwiftUI

struct PlayerScreen: View {

    let item: VideoItem
    var onStateChange: ((PlaybackState) -> Void)?
    var onProgress: ((Double, Double) -> Void)?

    @StateObject private var engine = PlayerEngine()
    @StateObject private var pip = PiPManager()
    @StateObject private var captions = LiveCaptionEngine()
    @ObservedObject private var history = HistoryStore.shared

    @State private var activeItem: VideoItem
    @State private var isFullscreen = false
    @State private var controlsVisible = true
    @State private var hud: PlayerHUDKind?
    @State private var isResolving = true
    @State private var resolveError: String?
    @State private var hideWork: DispatchWorkItem?
    @State private var toast: String?

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

    // MARK: Body

    var body: some View {
        Group {
            #if canImport(Translation)
            if #available(iOS 17.4, *) {
                content
                    .translationTask(
                        TranslationSession.Configuration(
                            source: Locale.Language(identifier: "ja"),
                            target: Locale.Language(identifier: "zh-Hans")
                        )
                    ) { session in
                        SystemTranslationBridge.shared.attach(session)
                    }
            } else {
                content
            }
            #else
            content
            #endif
        }
        .navigationBarHidden(isFullscreen)
        .statusBar(hidden: isFullscreen)
        .background(Color.black.ignoresSafeArea())
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
        .onChange(of: captions.status) { text in
            if !text.isEmpty {
                showToast(text)
            }
        }
    }

    private var content: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                playerArea
                if !isFullscreen {
                    embeddedInfo
                }
            }

            captionOverlay
            toastOverlay
        }
    }

    // MARK: 播放器区域

    private var playerArea: some View {
        ZStack {
            PlayerSurface(player: engine.player, gravity: engine.gravity) { layer in
                pip.attach(layer: layer)
            }

            PlayerGestureLayer(engine: engine, hud: $hud) {
                toggleControls()
            }

            if isResolving {
                loadingOverlay
            } else if let message = resolveError {
                failureOverlay(message)
            } else {
                if engine.state.isBusy {
                    bufferingBadge
                }

                if controlsVisible {
                    PlayerControls(
                        engine: engine,
                        pip: pip,
                        title: activeItem.title,
                        isFullscreen: isFullscreen,
                        captionsOn: captions.isRunning,
                        onBack: handleBack,
                        onToggleFullscreen: toggleFullscreen,
                        onToggleCaptions: {
                            Task { await captions.toggle(engine: engine) }
                        }
                    )
                    .transition(.opacity)
                }

                if let hud = hud {
                    PlayerHUDView(hud: hud)
                }
            }
        }
        .aspectRatio(isFullscreen ? nil : 16.0 / 9.0, contentMode: isFullscreen ? .fill : .fit)
        .frame(maxWidth: .infinity, maxHeight: isFullscreen ? .infinity : nil)
        .background(Color.black)
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
                Button("重试") {
                    Task { await resolve(activeItem) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.kanAccent))
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

    // MARK: 字幕 / Toast

    @ViewBuilder private var captionOverlay: some View {
        if captions.isRunning, let caption = captions.liveCaption, !caption.source.isEmpty {
            VStack {
                Spacer()
                VStack(spacing: 3) {
                    Text(caption.target.isEmpty ? caption.source : caption.target)
                        .font(.system(size: isFullscreen ? 18 : 15, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    if captions.showTranslation && !caption.target.isEmpty {
                        Text(caption.source)
                            .font(.system(size: isFullscreen ? 12 : 11))
                            .foregroundColor(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55))
                .cornerRadius(9)
                .padding(.horizontal, 24)
                .padding(.bottom, isFullscreen ? 92 : 16)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var toastOverlay: some View {
        if let text = toast {
            VStack {
                Spacer().frame(height: 54)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(16)
                Spacer()
            }
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    // MARK: 内嵌信息区

    private var embeddedInfo: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activeItem.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Text(activeItem.subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        if captions.isRunning {
                            Text("实时字幕 ON")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.kanAccent)
                        }
                    }
                }

                if !history.items.isEmpty {
                    Text("最近观看")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))

                    ForEach(history.items) { entry in
                        Button {
                            play(entry)
                        } label: {
                            VideoRow(item: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
        .background(Color.kanBackground)
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
        captions.stop()
        pip.stop()
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

        do {
            let html = try await Net.html(path: target.playPath)
            guard let source = Parser.playSource(from: html, fallbackTitle: target.title) else {
                throw KanError.noPlayURL
            }
            engine.load(url: source.url, autoplay: true)
            isResolving = false
            showControls()
        } catch let error {
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
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleHideControls()
        }
    }

    private func showControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideWork?.cancel()
        guard engine.state.isPlaying else { return }
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = false
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                if toast == text {
                    toast = nil
                }
            }
        }
    }
}
