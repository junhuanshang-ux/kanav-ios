import SwiftUI

/// 选择播放列表（播放页弹出）
struct PlaylistPickerSheet: View {

    let item: VideoItem
    @Binding var isPresented: Bool

    @ObservedObject private var store = PlaylistStore.shared

    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    Button {
                        showCreate = true
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color.kanAccent)
                            Text("新建播放列表")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.kanTextPrimary)
                            Spacer()
                        }
                        .padding(Spacing.md)
                        .background(Color.kanCard)
                        .cornerRadius(Radius.md)
                    }
                    .buttonStyle(.plain)

                    if store.playlists.isEmpty {
                        EmptyStateView(
                            icon: "list.bullet",
                            title: "还没有列表",
                            message: "新建一个把这部放进去"
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(store.playlists) { playlist in
                            Button {
                                let already = playlist.items.contains { $0.id == item.id }
                                if already {
                                    store.remove(item, from: playlist.id)
                                } else {
                                    store.add(item, to: playlist.id)
                                }
                                isPresented = false
                            } label: {
                                row(playlist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color.kanBackground.ignoresSafeArea())
            .navigationTitle("加入播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { isPresented = false }
                        .foregroundColor(Color.kanAccent)
                }
            }
            .alert("新建播放列表", isPresented: $showCreate) {
                TextField("名称", text: $newName)
                Button("取消", role: .cancel) { newName = "" }
                Button("创建") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let list = store.createPlaylist(name: name)
                    store.add(item, to: list.id)
                    newName = ""
                    isPresented = false
                }
            }
        }
        .preferredColorScheme(nil)
    }

    private func row(_ playlist: PlaylistStore.Playlist) -> some View {
        let contains = playlist.items.contains { $0.id == item.id }

        return HStack(spacing: Spacing.md) {
            Image(systemName: contains ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(contains ? Color.kanAccent : Color.kanTextSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.kanTextPrimary)
                Text("\(playlist.items.count) 个视频")
                    .font(.system(size: 11))
                    .foregroundColor(Color.kanTextSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(Color.kanCard)
        .cornerRadius(Radius.md)
    }
}
