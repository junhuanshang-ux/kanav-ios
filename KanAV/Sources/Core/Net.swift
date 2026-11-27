import Foundation

enum Net {

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpAdditionalHeaders = ["Accept-Language": "zh-CN,zh;q=0.9"]
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// jable 挂在 Cloudflare 后面，普通请求必然 403。
    /// 先试一次 URLSession（万一 cookie 已就绪、或某些路径没设防），失败再交给 WebFetcher。
    static func html(path: String, allowManualCheck: Bool = true) async throws -> String {
        let url = Site.url(path)

        if let text = try? await direct(url), !WebFetcher.looksLikeChallenge(text), text.count > 1200 {
            return text
        }
        guard let text = await WebFetcher.shared.html(url, allowManualCheck: allowManualCheck) else {
            throw KanError.challenge
        }
        if WebFetcher.looksLikeChallenge(text) {
            throw KanError.challenge
        }
        return text
    }

    /// 直连（给 m3u8 / 分片这类不需要 JS 的资源用）
    static func direct(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Site.base + "/", forHTTPHeaderField: "Referer")
        if let cookie = WebFetcher.shared.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw KanError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw KanError.emptyBody }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw KanError.decodeFailed
    }

    static func cookieHeader(for url: URL) -> String? {
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        guard !cookies.isEmpty else { return nil }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
