import SwiftUI

struct LibraryView: View {

    @ObservedObject private var store = HistoryStore.shared
    @ObservedObject private var lock = AppLock.shared
    @ObservedObject private var fetcher = WebFetcher.shared
    @AppStorage("player.useWeb") private var useWebPlayer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("最近观看")

                if store.items.isEmpty {
                    emptyHistory
                } else {
                    ForEach(store.items) { item in
                        NavigationLink(destination: PlayerScreen(item: item)) {
                            VideoRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.remove(item)
                            } label: {
                                Label("从记录中移除", systemImage: "trash")
                            }
                        }
                    }
                }

                sectionTitle("播放")

                settingsCard {
                    Toggle(isOn: $useWebPlayer) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("网页播放器")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Text(useWebPlayer
                                 ? "站点自带播放器，兼容性兜底（控件是网页的）"
                                 : "内置播放器：m3u8 / 分片统一走资源代理带鉴权，支持倍速、手势、比例切换")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color.kanAccent))
                }

                sectionTitle("安全")

                settingsCard {
                    Toggle(isOn: $lock.isEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(lock.biometryName) 解锁")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Text(lock.isBiometryAvailable
                                 ? "启动 App、从后台返回时需要验证"
                                 : "当前设备未设置生物识别，开关会退回密码验证")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color.kanAccent))
                }

                sectionTitle("关于")

                settingsCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("博客")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Text("数据来源 \(Site.base)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Text("采集用网页（过 Cloudflare 验证），播放用系统 AVPlayer。")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                sectionTitle("诊断")

                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("列表条目不全时，把最近抓到的页面导出发我，好按真实结构调解析。")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            exportDebugHTML()
                        } label: {
                            Text("导出抓取到的 HTML")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)

                        Text(lastFetchSummary)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))

                        Divider().background(Color.white.opacity(0.08))

                        Text("闪退时先重开 App，再点下面导出日志发我。")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            exportCrashLog()
                        } label: {
                            Text(CrashLogger.hasLog ? "导出崩溃日志" : "暂无崩溃日志")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(CrashLogger.hasLog
                                                           ? Color.kanAccent
                                                           : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!CrashLogger.hasLog)
                    }
                }
            }
            .padding(14)
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !store.items.isEmpty {
                    Button("清空") {
                        store.clear()
                    }
                    .foregroundColor(Color.kanAccent)
                }
            }
        }
    }

    private var emptyHistory: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 26))
                    .foregroundColor(.gray)
                Text("还没有观看记录")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.vertical, 28)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.85))
            .padding(.top, 4)
    }

    private var lastFetchSummary: String {
        let count = fetcher.lastHTML.count
        if count == 0 {
            return "还没有抓取记录（先浏览一次列表）"
        }
        return "上次抓取：\(count) 字符"
    }

    private func exportDebugHTML() {
        let html = fetcher.lastHTML
        guard !html.isEmpty else { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kanav-debug.html")
        try? html.write(to: url, atomically: true, encoding: .utf8)
        share(url)
    }

    private func exportCrashLog() {
        let text = CrashLogger.logText
        guard !text.isEmpty else { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kanav-crash.log")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        share(url)
    }

    private func share(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController
        else { return }

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(
                x: root.view.bounds.midX,
                y: root.view.bounds.midY,
                width: 1,
                height: 1
            )
        }
        root.present(activity, animated: true)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kanCard)
            .cornerRadius(12)
    }
}
