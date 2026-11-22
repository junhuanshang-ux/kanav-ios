import AVFoundation
import AVKit
import UIKit

/// 画中画：把 AVPictureInPictureController 绑到 AVPlayerLayer 上。
/// 需要 App 开启 Background Modes → Audio（project.yml 已配置）。
final class PiPManager: NSObject, ObservableObject {

    @Published private(set) var isSupported = false
    @Published private(set) var isActive = false

    private var controller: AVPictureInPictureController?
    private weak var attachedLayer: AVPlayerLayer?

    override init() {
        super.init()
        isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    }

    func attach(layer: AVPlayerLayer) {
        guard attachedLayer !== layer || controller == nil else { return }
        attachedLayer = layer
        controller?.delegate = nil
        controller = nil

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isSupported = false
            return
        }
        let newController = AVPictureInPictureController(playerLayer: layer)
        newController?.delegate = self
        newController?.canStartPictureInPictureAutomaticallyFromInline = true
        controller = newController
        isSupported = newController != nil
    }

    func toggle() {
        guard let controller = controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = true }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isActive = false }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        DispatchQueue.main.async { self.isActive = false }
    }
}
