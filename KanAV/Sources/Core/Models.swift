import Foundation

// MARK: - 站点配置

enum Site {
    /// 站点根地址
    static let base = "https://jable.tv"

    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 顶部分类。jable 是路径式路由，分页用 ?page=N
    static let categories: [Category] = [
        Category(id: 0, name: "最新", basePath: "/latest-updates/"),
        Category(id: 1, name: "热门", basePath: "/hot/"),
        Category(id: 2, name: "新作", basePath: "/new-release/"),
        Category(id: 3, name: "中文字幕", basePath: "/categories/chinese-subtitle/"),
        Category(id: 4, name: "无码", basePath: "/categories/uncensored/"),
        Category(id: 5, name: "破解马赛克", basePath: "/categories/reducing-mosaic/"),
        Category(id: 6, name: "素人", basePath: "/categories/amateur/"),
        Category(id: 7, name: "VR", basePath: "/categories/vr/")
    ]

    static func url(_ path: String) -> URL {
        if path.hasPrefix("http"), let u = URL(string: path) { return u }
        if path.hasPrefix("/"), let u = URL(string: base + path) { return u }
        if let u = URL(string: base + "/" + path) { return u }
        return URL(string: base)!
    }

    static func searchPath(_ keyword: String) -> String {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? keyword
        return "/search/" + encoded + "/"
    }
}

// MARK: - 模型

struct Category: Identifiable, Hashable {
    let id: Int
    let name: String
    let basePath: String

    func pagePath(_ page: Int) -> String {
        guard page > 1 else { return basePath }
        return basePath + "?page=\(page)"
    }
}

struct VideoItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let cover: String
    let duration: String
    /// 详情页路径（jable: /videos/{slug}/）
    let playPath: String

    var coverURL: URL? {
        guard !cover.isEmpty, let u = URL(string: cover) else { return nil }
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
    case challenge

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "服务器返回 \(code)，稍后重试"
        case .emptyBody: return "返回内容为空"
        case .decodeFailed: return "网页内容解析失败"
        case .noPlayURL: return "这条暂时解析不出播放地址"
        case .challenge: return "站点人机验证未通过，请重试"
        }
    }
}
