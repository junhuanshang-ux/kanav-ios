import SwiftUI
import UIKit

/// 方向控制：SwiftUI App 生命周期下需要 AppDelegate 才能按页面锁方向。
final class OrientationDelegate: NSObject, UIApplicationDelegate {

    static var mask: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationDelegate.mask
    }
}

enum OrientationSupport {

    static func enterLandscape() {
        apply(.landscapeRight, preferred: .landscapeRight)
    }

    static func enterPortrait() {
        apply(.portrait, preferred: .portrait)
    }

    static func restoreDefault() {
        apply(.portrait, preferred: .portrait)
    }

    private static func apply(_ mask: UIInterfaceOrientationMask, preferred: UIInterfaceOrientation) {
        OrientationDelegate.mask = mask

        if #available(iOS 16.0, *) {
            guard let scene = activeScene() else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            var root = scene.keyWindow?.rootViewController
            while let presented = root?.presentedViewController {
                root = presented
            }
            root?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIDevice.current.setValue(preferred.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// 隐藏 / 显示底部 TabBar（iOS 15 没有 .toolbar(for: .tabBar)）
    static func setTabBarHidden(_ hidden: Bool) {
        guard let scene = activeScene(),
              let window = scene.keyWindow,
              let tabBar = findTabBar(in: window.rootViewController)
        else { return }
        tabBar.isHidden = hidden
    }

    private static func findTabBar(in controller: UIViewController?) -> UITabBar? {
        guard let controller = controller else { return nil }
        if let tab = controller as? UITabBarController {
            return tab.tabBar
        }
        for child in controller.children {
            if let found = findTabBar(in: child) {
                return found
            }
        }
        return findTabBar(in: controller.presentedViewController)
    }
}
