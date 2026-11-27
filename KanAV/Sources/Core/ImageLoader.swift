import Foundation
import UIKit

/// 封面走的是独立 CDN（static.javcdn.vip），带防盗链：
/// 裸 URLSession 没有 Referer 会被直接拒，所以自己发请求、自己缓存。
final class ImageLoader {

    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        cache.countLimit = 240
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        var request = URLRequest(url: url)
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Site.base + "/", forHTTPHeaderField: "Referer")
        request.setValue("image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let cookie = Net.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let image = UIImage(data: data)
        else { return nil }

        cache.setObject(image, forKey: key)
        return image
    }
}
