import SwiftUI

/// 播放页分发：默认走网页播放器（站点自带播放器，CF/CDN 鉴权天然一致），
/// 设置里关掉则回到原生 AVPlayer 播放器。
struct PlayerScreen: View {

    let item: VideoItem

    @AppStorage("player.useWeb") private var useWebPlayer = false

    var body: some View {
        if useWebPlayer {
            WebPlayerView(item: item)
        } else {
            NativePlayerScreen(item: item)
        }
    }
}
