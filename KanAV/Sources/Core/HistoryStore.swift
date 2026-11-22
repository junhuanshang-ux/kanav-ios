import Foundation

/// 最近观看，本地持久化，最多 60 条。
final class HistoryStore: ObservableObject {

    static let shared = HistoryStore()

    @Published private(set) var items: [VideoItem] = []

    private let key = "kanav.history.v1"
    private let limit = 60

    private init() {
        load()
    }

    func record(_ item: VideoItem) {
        var list = items.filter { $0.id != item.id }
        list.insert(item, at: 0)
        if list.count > limit {
            list = Array(list.prefix(limit))
        }
        items = list
        persist()
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
