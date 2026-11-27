import SwiftUI

struct LibraryView: View {

    @ObservedObject private var store = HistoryStore.shared
    @ObservedObject private var lock = AppLock.shared

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
                        Text("播放器使用系统 AVPlayer，支持 HLS / 多音轨 / 内嵌字幕 / 画中画。")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .fixedSize(horizontal: false, vertical: true)
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

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kanCard)
            .cornerRadius(12)
    }
}
