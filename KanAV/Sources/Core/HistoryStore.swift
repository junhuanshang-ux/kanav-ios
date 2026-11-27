import Foundation

/// 最近观看 + 观看进度，本地持久化。
final class HistoryStore: ObservableObject {

    static let shared = HistoryStore()

    @Published private(set) var items: [VideoItem] = []
    /// 视频 id → 已看到第几秒
    @Published private(set) var progressMap: [String: Double] = [:]

    private let key = "kanav.history.v1"
    private let progressKey = "kanav.progress.v1"
    private let limit = 60

    private init() {
        load()
        loadProgress()
    }

    // MARK: 记录

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
        progressMap.removeValue(forKey: item.id)
        persist()
        persistProgress()
    }

    func clear() {
        items = []
        progressMap = [:]
        persist()
        persistProgress()
    }

    // MARK: 进度

    func progress(for id: String) -> Double {
        progressMap[id] ?? 0
    }

    /// 播放过程中持续调用；看到接近结尾就把进度清掉，下次从头放
    func updateProgress(_ seconds: Double, duration: Double, for id: String) {
        guard seconds.isFinite, duration.isFinite, duration > 60 else { return }
        guard seconds > 3 else { return }

        if seconds > duration - 45 {
            guard progressMap[id] != nil else { return }
            progressMap.removeValue(forKey: id)
        } else {
            let existing = progressMap[id] ?? 0
            // 每前进 2 秒才写一次，避免频繁落盘
            guard abs(existing - seconds) >= 2 else { return }
            progressMap[id] = seconds
        }
        persistProgress()
    }

    func clearProgress(for id: String) {
        progressMap.removeValue(forKey: id)
        persistProgress()
    }

    // MARK: 持久化

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

    private func loadProgress() {
        guard let raw = UserDefaults.standard.dictionary(forKey: progressKey) else { return }
        var map: [String: Double] = [:]
        for (k, v) in raw {
            if let number = v as? Double { map[k] = number }
            else if let number = v as? NSNumber { map[k] = number.doubleValue }
        }
        progressMap = map
    }

    private func persistProgress() {
        UserDefaults.standard.set(progressMap, forKey: progressKey)
    }
}
