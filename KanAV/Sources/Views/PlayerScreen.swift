import AVKit
import SwiftUI

struct PlayerScreen: View {

    let item: VideoItem

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var resolvedTitle: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let current = player {
                PlayerContainer(player: current)
                    .ignoresSafeArea()
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("正在解析播放地址…")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    Text(errorText ?? "播放失败")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("重试") {
                        Task { await resolve() }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.kanAccent))
                }
            }
        }
        .navigationTitle(resolvedTitle ?? item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            HistoryStore.shared.record(item)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            player?.pause()
            player = nil
        }
        .task {
            await resolve()
        }
    }

    private func resolve() async {
        isLoading = true
        errorText = nil
        player?.pause()
        player = nil

        do {
            let html = try await Net.html(path: item.playPath)
            guard let source = Parser.playSource(from: html, fallbackTitle: item.title) else {
                throw KanError.noPlayURL
            }
            resolvedTitle = source.title

            let fresh = AVPlayer(url: source.url)
            fresh.automaticallyWaitsToMinimizeStalling = true
            player = fresh
            fresh.play()
        } catch let error {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}

/// AVPlayerViewController 的 SwiftUI 包装：内置全屏、AirPlay、手势。
struct PlayerContainer: UIViewControllerRepresentable {

    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}
