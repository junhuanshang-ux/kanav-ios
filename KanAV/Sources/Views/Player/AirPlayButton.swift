import AVKit
import SwiftUI

/// 系统投屏按钮（AVRoutePickerView），点开就是 AirPlay 设备列表。
struct AirPlayButton: UIViewRepresentable {

    var tint: UIColor = .white
    var activeTint: UIColor = UIColor(red: 1.0, green: 0.23, blue: 0.36, alpha: 1)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = activeTint
        view.prioritizesVideoDevices = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tint
        uiView.activeTintColor = activeTint
    }
}
