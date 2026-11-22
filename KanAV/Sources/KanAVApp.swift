import AVFoundation
import SwiftUI

@main
struct KanAVApp: App {

    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientationDelegate

    init() {
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
    static let kanAccent = Color(red: 1.0, green: 0.18, blue: 0.33)
    static let kanBackground = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let kanCard = Color(red: 0.11, green: 0.11, blue: 0.13)
}
