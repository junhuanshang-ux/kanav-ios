import AVFoundation
import Foundation

/// 播放地址预检。
///
/// 直接把 m3u8 丢给 AVPlayer 会有两个问题：
///   1. 有些地址是 master playlist（多码率），AVPlayer 不一定选得对，表现就是"转圈不出画面"
///   2. 地址失效 / 403 时 AVPlayer 会一直等，用户看到的是无限缓冲
///
/// 所以先自己带 Referer + Cookie 拉一次，确认是 `#EXTM3U`；
/// 如果是 master playlist，解析出最高码率的子流再交给播放器。
enum StreamResolver {

    struct Resolved {
        let url: URL
        let referer: String
        let userAgent: String
    }

    static func resolve(_ raw: URL, referer: String) async throws -> Resolved {
        var request = URLRequest(url: raw)
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if let cookie = Net.cookieHeader(for: raw) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.timeoutInterval = 4

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            throw KanError.badStatus(-1)
        }
        guard let http = response as? HTTPURLResponse else {
            throw KanError.decodeFailed
        }
        guard (200...299).contains(http.statusCode) else {
            throw KanError.badStatus(http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8), text.contains("#EXTM3U") else {
            // 不是 m3u8：可能是 iframe 播放器页或直链 mp4
            if let type = http.value(forHTTPHeaderField: "Content-Type"),
               type.contains("video") || type.contains("mp4") {
                return Resolved(url: raw, referer: referer, userAgent: Site.userAgent)
            }
            throw KanError.noPlayURL
        }

        if text.contains("#EXT-X-STREAM-INF"),
           let best = bestVariant(in: text, base: raw) {
            return Resolved(url: best, referer: referer, userAgent: Site.userAgent)
        }
        return Resolved(url: raw, referer: referer, userAgent: Site.userAgent)
    }

    /// master playlist：取带宽最高的子流
    private static func bestVariant(in text: String, base: URL) -> URL? {
        var candidates: [(url: URL, bandwidth: Int)] = []
        var pendingBandwidth = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                if let range = line.range(of: "BANDWIDTH=") {
                    let digits = line[range.upperBound...].prefix { $0.isNumber }
                    pendingBandwidth = Int(digits) ?? 0
                }
            } else if !line.isEmpty, !line.hasPrefix("#") {
                if let url = URL(string: line, relativeTo: base)?.absoluteURL {
                    candidates.append((url, pendingBandwidth))
                }
                pendingBandwidth = 0
            }
        }

        return candidates.max { $0.bandwidth < $1.bandwidth }?.url
    }
}
