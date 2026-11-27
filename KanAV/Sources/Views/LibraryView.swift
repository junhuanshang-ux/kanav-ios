import SwiftUI

/// 「我的」页：收藏 / 最近观看入口 + 外观 / 存储 / 安全 / 关于
struct LibraryView: View {

    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var lock = AppLock.shared
    @ObservedObject private var playlists = PlaylistStore.shared

    @AppStorage("app.theme") private var themeRaw = ThemeMode.system.rawValue
    @AppStorage("player.autoNext") private var autoNext = true
    @AppStorage("notify.daily") private var dailyReminder = false
    @AppStorage("notify.hour") private var reminderHour = 20
    @AppStorage("notify.minute") private var reminderMinute = 0
    @AppStorage("gesture.mirror") private var mirrorGesture = false
    @AppStorage("gesture.boostSpeed") private var boostSpeed = 2.0

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = reminderHour
                components.minute = reminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = components.hour ?? 20
                reminderMinute = components.minute ?? 0
            }
        )
    }

    @State private var isClearing = false
    @State private var clearMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                HStack(spacing: Spacing.sm) {
                    NavigationLink {
                        FavoritesView()
                    } label: {
                        entryCard(title: "收藏", count: favorites.items.count, icon: "heart.fill")
                    }
                    .buttonStyle(CardButtonStyle())

                    NavigationLink {
                        RecentView()
                    } label: {
                        entryCard(title: "最近", count: history.items.count, icon: "clock.arrow.circlepath")
                    }
                    .buttonStyle(CardButtonStyle())

                    NavigationLink {
                        PlaylistsView()
                    } label: {
                        entryCard(title: "列表", count: playlists.playlists.count, icon: "list.bullet.rectangle")
                    }
                    .buttonStyle(CardButtonStyle())
                }

                sectionTitle("外观")
                card {
                    Picker("主题", selection: $themeRaw) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                sectionTitle("播放")
                card {
                    Toggle(isOn: $autoNext) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动连播")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.kanTextPrimary)
                            Text("播完后自动接「猜你喜欢」的第一部")
                                .font(.system(size: 11))
                                .foregroundColor(Color.kanTextSecondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color.kanAccent))
                }

                NavigationLink {
                    ComboFilterView()
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color.kanAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("组合筛选")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.kanTextPrimary)
                            Text("同时选多个标签，取交集")
                                .font(.system(size: 11))
                                .foregroundColor(Color.kanTextSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.kanTextSecondary)
                    }
                    .padding(Spacing.md)
                    .background(Color.kanCard)
                    .cornerRadius(Radius.md)
                }
                .buttonStyle(CardButtonStyle())

                sectionTitle("提醒")
                card {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Toggle(isOn: $dailyReminder) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("每日更新提醒")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color.kanTextPrimary)
                                Text("到点提醒今天有上新")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.kanTextSecondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.kanAccent))

                        if dailyReminder {
                            DatePicker(
                                "时间",
                                selection: $reminderTime,
                                displayedComponents: .hourAndMinute
                            )
                            .font(.system(size: 13))
                            .foregroundColor(Color.kanTextPrimary)
                            .datePickerStyle(.compact)
                        }
                    }
                }

                sectionTitle("手势")
                card {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Toggle(isOn: $mirrorGesture) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("左右手模式")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color.kanTextPrimary)
                                Text("左半屏调音量、右半屏调亮度")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.kanTextSecondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.kanAccent))

                        VStack(alignment: .leading, spacing: 5) {
                            Text("长按快进倍率")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.kanTextPrimary)
                            Picker("长按快进倍率", selection: $boostSpeed) {
                                Text("2×").tag(2.0)
                                Text("3×").tag(3.0)
                                Text("4×").tag(4.0)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                sectionTitle("存储")
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            clearCache()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(isClearing ? "清理中…" : "清除缓存")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                if isClearing {
                                    ProgressView().scaleEffect(0.7)
                                }
                            }
                            .foregroundColor(Color.kanTextPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.kanSurface)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isClearing)

                        if let message = clearMessage {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundColor(Color.kanTextSecondary)
                        } else {
                            Text("只清图片和播放地址缓存，登录状态与人机验证会保留")
                                .font(.system(size: 11))
                                .foregroundColor(Color.kanTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                sectionTitle("安全")
                card {
                    Toggle(isOn: $lock.isEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(lock.biometryName) 解锁")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.kanTextPrimary)
                            Text(lock.isBiometryAvailable
                                 ? "启动 App、从后台返回时需要验证"
                                 : "当前设备未设置生物识别，开关会退回密码验证")
                                .font(.system(size: 11))
                                .foregroundColor(Color.kanTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color.kanAccent))
                }

                sectionTitle("关于")
                card {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("博客")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.kanTextPrimary)
                        Text("数据来源 \(Site.base)")
                            .font(.system(size: 11))
                            .foregroundColor(Color.kanTextSecondary)
                        Text("采集用网页（过 Cloudflare 验证），播放用系统 AVPlayer。")
                            .font(.system(size: 11))
                            .foregroundColor(Color.kanTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: dailyReminder) { enabled in
            applyReminder(enabled)
        }
        .onChange(of: reminderHour) { _ in
            if dailyReminder { NotificationManager.shared.scheduleDaily(hour: reminderHour, minute: reminderMinute) }
        }
        .onChange(of: reminderMinute) { _ in
            if dailyReminder { NotificationManager.shared.scheduleDaily(hour: reminderHour, minute: reminderMinute) }
        }
    }

    private func applyReminder(_ enabled: Bool) {
        guard enabled else {
            NotificationManager.shared.cancel()
            return
        }
        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            await MainActor.run {
                if granted {
                    NotificationManager.shared.scheduleDaily(hour: reminderHour, minute: reminderMinute)
                } else {
                    dailyReminder = false
                }
            }
        }
    }

    // MARK: 组件

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.kanSurface)
                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color.kanTextSecondary)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("博客")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.kanTextPrimary)
                Text("\(favorites.items.count) 个收藏 · \(history.items.count) 条记录")
                    .font(.system(size: 11))
                    .foregroundColor(Color.kanTextSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func entryCard(title: String, count: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.kanAccent)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.kanTextPrimary)

            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.kanTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.kanCard)
        .cornerRadius(12)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color.kanTextSecondary)
            .padding(.top, 4)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kanCard)
            .cornerRadius(12)
    }

    private func clearCache() {
        guard !isClearing else { return }
        isClearing = true
        clearMessage = nil
        Task {
            let result = await CacheCleaner.clear()
            await MainActor.run {
                isClearing = false
                clearMessage = result.description
            }
        }
    }
}

// MARK: - 收藏

struct FavoritesView: View {

    @ObservedObject private var store = FavoritesStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        Group {
            if store.items.isEmpty {
                emptyState(icon: "heart", text: "还没有收藏\n在播放页点右上角的心形按钮")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(store.items) { item in
                            NavigationLink(destination: PlayerScreen(item: item)) {
                                VideoCard(item: item)
                            }
                            .buttonStyle(CardButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.remove(item)
                                } label: {
                                    Label("取消收藏", systemImage: "heart.slash")
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(Color.kanTextSecondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color.kanTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 最近观看

struct RecentView: View {

    @ObservedObject private var store = HistoryStore.shared

    var body: some View {
        Group {
            if store.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30))
                        .foregroundColor(Color.kanTextSecondary)
                    Text("还没有观看记录")
                        .font(.system(size: 12))
                        .foregroundColor(Color.kanTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(store.items) { item in
                            NavigationLink(destination: PlayerScreen(item: item)) {
                                VideoRow(item: item)
                            }
                            .buttonStyle(CardButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.remove(item)
                                } label: {
                                    Label("从记录中移除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("最近观看")
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
}
