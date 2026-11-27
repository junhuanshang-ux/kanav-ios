import AVFoundation
import SwiftUI

@main
struct KanAVApp: App {

    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientationDelegate

    init() {
        CrashLogger.install()

        // 视频站：静音键打开也要出声
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.kanAccent)
        }
    }
}

struct RootView: View {

    @ObservedObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app.theme") private var themeRaw = ThemeMode.system.rawValue

    private var scheme: ColorScheme? {
        ThemeMode(rawValue: themeRaw)?.colorScheme
    }

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
        .preferredColorScheme(scheme)
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                lock.lockIfNeeded()
            }
        }
    }
}

// MARK: - 主题

enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .dark: return "深色"
        case .light: return "浅色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

extension Color {

    /// 强调色（番号、选中态、进度条）
    static let kanAccent = Color(red: 1.0, green: 0.23, blue: 0.36)

    /// 页面底色
    static let kanBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
            : UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    })

    /// 卡片 / 封面占位
    static let kanCard = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
            : UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1)
    })

    /// 胶囊、按钮底
    static let kanSurface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.13, blue: 0.16, alpha: 1)
            : UIColor(red: 0.89, green: 0.89, blue: 0.92, alpha: 1)
    })

    /// 主文字
    static let kanTextPrimary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
    })

    /// 次级文字
    static let kanTextSecondary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.60, alpha: 1)
            : UIColor(white: 0.42, alpha: 1)
    })

    /// 译文专用色
    static let kanTranslated = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.84, blue: 1.0, alpha: 1)
            : UIColor(red: 0.04, green: 0.46, blue: 0.78, alpha: 1)
    })
}
