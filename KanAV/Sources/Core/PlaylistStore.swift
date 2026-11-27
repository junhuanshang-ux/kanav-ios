import Foundation

/// 播放列表：多个自定义列表，每个列表存若干视频。
final class PlaylistStore: ObservableObject {

    static let shared = PlaylistStore()

    struct Playlist: Identifiable, Codable, Hashable {
        let id: String
        var name: String
        var items: [VideoItem]
        var createdAt: Date

        var cover: String {
            items.first?.cover ?? ""
        }
    }

    @Published private(set) var playlists: [Playlist] = []

    private let key = "kanav.playlists.v1"

    private init() {
        load()
    }

    // MARK: 查询

    func contains(_ item: VideoItem) -> Bool {
        playlists.contains { $0.items.contains { $0.id == item.id } }
    }

    func playlist(containing item: VideoItem) -> Playlist? {
        playlists.first { $0.items.contains { $0.id == item.id } }
    }

    // MARK: 修改

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let list = Playlist(
            id: UUID().uuidString,
            name: name,
            items: [],
            createdAt: Date()
        )
        playlists.insert(list, at: 0)
        persist()
        return list
    }

    func add(_ item: VideoItem, to playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        guard !playlists[index].items.contains(where: { $0.id == item.id }) else { return }
        playlists[index].items.insert(item, at: 0)
        persist()
    }

    func remove(_ item: VideoItem, from playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].items.removeAll { $0.id == item.id }
        persist()
    }

    func delete(_ playlistID: String) {
        playlists.removeAll { $0.id == playlistID }
        persist()
    }

    func rename(_ playlistID: String, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].name = name
        persist()
    }

    // MARK: 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data)
        else { return }
        playlists = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
