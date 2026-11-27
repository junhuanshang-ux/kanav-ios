import Foundation

/// 播放地址缓存。
///
/// 一个视频的 m3u8 地址在 10 分钟内一般不会变，但每次进来都要：
/// 抓视频页 HTML → 正则提 m3u8 → 预检 → 才算拿到。重复打开同一个片会很慢。
/// 这里缓存解析结果，二次播放直接起播。
final class PlayURLCache {

    static let shared = PlayURLCache()

    private struct Entry {
        let url: URL
        let referer: String
        let date: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 600
    private let limit = 40

    private init() {}

    func get(_ key: String) -> (url: URL, referer: String)? {
        guard let entry = entries[key] else { return nil }
        guard Date().timeIntervalSince(entry.date) < ttl else {
            entries.removeValue(forKey: key)
            return nil
        }
        return (entry.url, entry.referer)
    }

    func set(_ key: String, url: URL, referer: String) {
        if entries.count >= limit {
            // 简单淘汰：清掉最旧的一半
            let sorted = entries.sorted { $0.value.date < $1.value.date }
            for pair in sorted.prefix(limit / 2) {
                entries.removeValue(forKey: pair.key)
            }
        }
        entries[key] = Entry(url: url, referer: referer, date: Date())
    }

    func clear() {
        entries.removeAll()
    }
}
