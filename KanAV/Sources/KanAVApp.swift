import AVFoundation
import SwiftUI

@main
struct KanAVApp: App {

    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientationDelegate

    init() {
        CrashLogger.install()

        // 视频站：静音键打开也要出声，并支持后台/画中画音频
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Color.kanAccent)
        }
    }
}

struct RootView: View {

    @ObservedObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TabView {
                NavigationView {
                    HomeView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("发现", systemImage: "play.rectangle.fill") }

                NavigationView {
                    SearchView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }

                NavigationView {
                    LibraryView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
            }

            if lock.isLocked {
                LockScreen()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                lock.lockIfNeeded()
            }
        }
    }
}

// MARK: - 主题

extension Color {
    /// 强调色（番号、选中态、进度条）
    static let kanAccent = Color(red: 1.0, green: 0.23, blue: 0.36)
    /// 页面底色
    static let kanBackground = Color(red: 0.04, green: 0.04, blue: 0.05)
    /// 卡片 / 封面底
    static let kanCard = Color(red: 0.10, green: 0.10, blue: 0.12)
    /// 胶囊、按钮底
    static let kanSurface = Color(red: 0.13, green: 0.13, blue: 0.16)
    /// 次级文字
    static let kanTextSecondary = Color(white: 0.60)
    /// 译文专用的浅青色，和原文区分开
    static let kanTranslated = Color(red: 0.42, green: 0.84, blue: 1.0)
}
