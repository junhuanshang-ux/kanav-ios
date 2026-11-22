import LocalAuthentication
import SwiftUI

/// App 锁：启动 / 回到前台时需要 面容 ID / 触控 ID 验证。
final class AppLock: ObservableObject {

    static let shared = AppLock()

    @Published private(set) var isLocked = false
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.key)
            if !isEnabled {
                isLocked = false
            }
        }
    }

    private static let key = "app.lock.enabled"
    private var isAuthenticating = false

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.key)
        isLocked = isEnabled
    }

    var biometryName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "生物识别"
        }
        switch context.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        default: return "生物识别"
        }
    }

    var isBiometryAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func lockIfNeeded() {
        guard isEnabled else { return }
        isLocked = true
    }

    func unlock() {
        guard isEnabled, isLocked, !isAuthenticating else { return }
        isAuthenticating = true

        let context = LAContext()
        context.localizedCancelTitle = "取消"
        context.localizedFallbackTitle = "输入密码"

        var error: NSError?
        let biometricsOnly = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let policy: LAPolicy = biometricsOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication

        context.evaluatePolicy(policy, localizedReason: "解锁「博客」") { success, _ in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    self.isLocked = false
                }
            }
        }
    }
}

struct LockScreen: View {

    @ObservedObject private var lock = AppLock.shared
    @State private var triedOnce = false

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: lock.isBiometryAvailable ? "faceid" : "lock.fill")
                    .font(.system(size: 46, weight: .light))
                    .foregroundColor(.white)

                Text("博客")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("已锁定，验证 \(lock.biometryName) 继续")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)

                Button {
                    lock.unlock()
                } label: {
                    Text("解锁")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 160, height: 44)
                        .background(Capsule().fill(Color.kanAccent))
                }
                .padding(.top, 8)
            }
        }
        .onAppear {
            guard !triedOnce else { return }
            triedOnce = true
            lock.unlock()
        }
    }
}
