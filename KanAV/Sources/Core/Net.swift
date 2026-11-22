import Foundation

/// 极简 HTTP 层：只抓 HTML，带站点要求的 UA / Referer。
enum Net {

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpAdditionalHeaders = ["Accept-Language": "zh-CN,zh;q=0.9"]
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    static func html(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Site.base + "/", forHTTPHeaderField: "Referer")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw KanError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw KanError.emptyBody }

        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw KanError.decodeFailed
    }

    static func html(path: String) async throws -> String {
        try await html(Site.url(path))
    }
}
