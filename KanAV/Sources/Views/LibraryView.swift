import SwiftUI

struct LibraryView: View {

    @ObservedObject private var store = HistoryStore.shared
    @ObservedObject private var lock = AppLock.shared
    @ObservedObject private var models = WhisperModelStore.shared

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

                sectionTitle("实时字幕")

                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Whisper.cpp 模型")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text(models.isDownloaded ? models.sizeText : "未下载")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }

                        if models.isDownloading {
                            ProgressView(value: models.progress)
                                .tint(Color.kanAccent)
                            Text("下载中 \(Int(models.progress * 100))%")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        } else if let error = models.errorText {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(WhisperEngine.isSupported
                                 ? "base-q5_1 · 本地推理，音频不出设备"
                                 : "当前构建不含 whisper.cpp，会回退系统识别")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if models.isDownloaded {
                            Button {
                                models.removeModel()
                            } label: {
                                actionLabel("删除模型", filled: false)
                            }
                            .buttonStyle(.plain)
                        } else if models.isDownloading {
                            Button {
                                models.cancel()
                            } label: {
                                actionLabel("取消下载", filled: false)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                models.download()
                            } label: {
                                actionLabel("下载模型（\(WhisperModelStore.approximateSize)）", filled: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("播放页控制条右侧的气泡按钮开关实时字幕：优先用 Whisper 本地推理，模型缺失时回退系统语音识别。")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
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

    private func actionLabel(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(filled ? Color.kanAccent : Color.white.opacity(0.12))
            )
    }
}
