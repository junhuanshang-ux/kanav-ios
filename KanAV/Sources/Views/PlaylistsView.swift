import SwiftUI

/// 播放列表总览
struct PlaylistsView: View {

    @ObservedObject private var store = PlaylistStore.shared

    @State private var showCreate = false
    @State private var newName = ""
    @State private var renaming: PlaylistStore.Playlist?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            if store.playlists.isEmpty {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "还没有播放列表",
                    message: "建一个列表，把想看的攒起来",
                    actionTitle: "新建列表"
                ) {
                    showCreate = true
                }
                .padding(.top, 80)
            } else {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(store.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlistID: playlist.id)
                        } label: {
                            row(playlist)
                        }
                        .buttonStyle(CardButtonStyle())
                        .contextMenu {
                            Button {
                                renaming = playlist
                                renameText = playlist.name
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                store.delete(playlist.id)
                            } label: {
                                Label("删除列表", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("播放列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Color.kanAccent)
            }
        }
        .alert("新建播放列表", isPresented: $showCreate) {
            TextField("名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("创建") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                store.createPlaylist(name: name)
                newName = ""
            }
        }
        .alert("重命名", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let playlist = renaming {
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { store.rename(playlist.id, to: name) }
                }
                renaming = nil
            }
        }
    }

    private func row(_ playlist: PlaylistStore.Playlist) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Color.kanCard
                if let url = URL(string: playlist.cover), !playlist.cover.isEmpty {
                    RemoteImage(url: url)
                } else {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                        .foregroundColor(Color.kanTextSecondary)
                }
            }
            .frame(width: 84, height: 48)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.kanTextPrimary)
                Text("\(playlist.items.count) 个视频")
                    .font(.system(size: 11))
                    .foregroundColor(Color.kanTextSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.kanTextSecondary)
        }
        .padding(Spacing.md)
        .background(Color.kanCard)
        .cornerRadius(Radius.md)
    }
}

/// 单个播放列表的内容
struct PlaylistDetailView: View {

    let playlistID: String

    @ObservedObject private var store = PlaylistStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var playlist: PlaylistStore.Playlist? {
        store.playlists.first { $0.id == playlistID }
    }

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: count)
    }

    var body: some View {
        Group {
            if let playlist = playlist, !playlist.items.isEmpty {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Spacing.xl) {
                        ForEach(playlist.items) { item in
                            NavigationLink(destination: PlayerScreen(item: item)) {
                                VideoCard(item: item)
                            }
                            .buttonStyle(CardButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.remove(item, from: playlistID)
                                } label: {
                                    Label("从列表移除", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                    .padding(Spacing.lg)
                }
            } else {
                EmptyStateView(
                    icon: "tray",
                    title: "列表是空的",
                    message: "在播放页点「加入列表」把视频放进来"
                )
                .padding(.top, 80)
            }
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle(playlist?.name ?? "播放列表")
        .navigationBarTitleDisplayMode(.inline)
    }
}
