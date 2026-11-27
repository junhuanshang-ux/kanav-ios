import SwiftUI

/// 播放页入口：统一走原生 AVPlayer 播放器。
struct PlayerScreen: View {

    let item: VideoItem
    var onStateChange: ((PlaybackState) -> Void)?
    var onProgress: ((Double, Double) -> Void)?

    var body: some View {
        NativePlayerScreen(
            item: item,
            onStateChange: onStateChange,
            onProgress: onProgress
        )
    }
}
