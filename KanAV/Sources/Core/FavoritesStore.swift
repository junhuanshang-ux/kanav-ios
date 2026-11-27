import Foundation

/// 收藏夹。本地持久化，按加入时间倒序。
final class FavoritesStore: ObservableObject {

    static let shared = FavoritesStore()

    @Published private(set) var items: [VideoItem] = []

    private let key = "kanav.favorites.v1"
    private let limit = 500

    private init() {
        load()
    }

    func contains(_ item: VideoItem) -> Bool {
        items.contains { $0.id == item.id }
    }

    /// 返回操作后的状态：true = 已收藏
    @discardableResult
    func toggle(_ item: VideoItem) -> Bool {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            persist()
            return false
        }
        items.insert(item, at: 0)
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        persist()
        return true
    }

    func remove(_ item: VideoItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([VideoItem].self, from: data)
        else { return }
        items = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
