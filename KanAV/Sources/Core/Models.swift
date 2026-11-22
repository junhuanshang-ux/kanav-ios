import Foundation

// MARK: - 站点配置

enum Site {
    /// 站点根地址。换站只改这里。
    static let base = "https://kanav.ad"

    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 顶部分类。id 与站点 /index.php/vod/type/id/{id}.html 对应，0 表示首页聚合流。
    static let categories: [Category] = [
        Category(id: 0, name: "最新"),
        Category(id: 1, name: "中文字幕"),
        Category(id: 2, name: "日韩有码"),
        Category(id: 3, name: "日韩无码"),
        Category(id: 4, name: "国产"),
        Category(id: 22, name: "自拍"),
        Category(id: 30, name: "泄密"),
        Category(id: 31, name: "探花"),
        Category(id: 32, name: "主播"),
        Category(id: 20, name: "动漫"),
        Category(id: 25, name: "里番"),
        Category(id: 27, name: "Motion"),
        Category(id: 28, name: "3D"),
        Category(id: 29, name: "同人")
    ]

    static func url(_ path: String) -> URL {
        if path.hasPrefix("http"), let u = URL(string: path) { return u }
        if path.hasPrefix("/"), let u = URL(string: base + path) { return u }
        if let u = URL(string: base + "/" + path) { return u }
        return URL(string: base)!
    }
}

// MARK: - 模型

struct Category: Identifiable, Hashable {
    let id: Int
    let name: String

    var firstPath: String {
        id == 0 ? "/" : "/index.php/vod/type/id/\(id).html"
    }

    func path(page: Int) -> String {
        guard page > 1 else { return firstPath }
        guard id != 0 else { return "/" }
        return "/index.php/vod/type/id/\(id)/page/\(page).html"
    }
}

struct VideoItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let cover: String
    let duration: String
    let playPath: String

    var coverURL: URL? {
        guard let u = URL(string: cover), !cover.isEmpty else { return nil }
        return u
    }

    var subtitle: String {
        duration.isEmpty ? "点击播放" : duration
    }

    static func == (lhs: VideoItem, rhs: VideoItem) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PlaySource {
    let title: String
    let url: URL
}

// MARK: - 错误

enum KanError: LocalizedError {
    case badStatus(Int)
    case emptyBody
    case decodeFailed
    case noPlayURL

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "服务器返回 \(code)，稍后重试"
        case .emptyBody: return "返回内容为空"
        case .decodeFailed: return "网页内容解析失败"
        case .noPlayURL: return "这条暂时解析不出播放地址"
        }
    }
}
