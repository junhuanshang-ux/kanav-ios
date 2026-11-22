import AVFoundation
import SwiftUI

/// AVPlayerLayer 宿主：自定义控件 + 画中画都需要拿到图层本身。
struct PlayerSurface: UIViewRepresentable {

    let player: AVPlayer
    let gravity: AVLayerVideoGravity
    let onLayerReady: (AVPlayerLayer) -> Void

    func makeUIView(context: Context) -> PlayerLayerHost {
        let host = PlayerLayerHost()
        host.backgroundColor = .black
        host.playerLayer.player = player
        host.playerLayer.videoGravity = gravity
        let layer = host.playerLayer
        DispatchQueue.main.async {
            onLayerReady(layer)
        }
        return host
    }

    func updateUIView(_ uiView: PlayerLayerHost, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != gravity {
            uiView.playerLayer.videoGravity = gravity
        }
    }
}

final class PlayerLayerHost: UIView {

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
