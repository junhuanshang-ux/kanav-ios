import Foundation

/// jable 的模板会变，所以解析不绑死 class：
/// 以「/videos/{slug}/」链接为锚点，在前后窗口里找封面、标题、时长。
enum Parser {

    // MARK: 基础

    private static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = makeRegex(pattern) else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: full) else { return nil }
        guard group < match.numberOfRanges else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }

    static func stripTags(_ raw: String) -> String {
        guard let regex = makeRegex("<[^>]+>") else { return raw }
        let ns = raw as NSString
        return regex.stringByReplacingMatches(
            in: raw, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    static func decodeEntities(_ raw: String) -> String {
        var text = raw
        let named = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
            "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}", "&hellip;": "\u{2026}"
        ]
        for (key, value) in named {
            text = text.replacingOccurrences(of: key, with: value)
        }
        guard let regex = makeRegex("&#(\\d+);") else { return text }
        var ns = text as NSString
        var matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        var guardCount = 0
        while let match = matches.first, guardCount < 512 {
            guardCount += 1
            let code = ns.substring(with: match.range(at: 1))
            var replacement = ""
            if let value = UInt32(code), let scalar = Unicode.Scalar(value) {
                replacement = String(scalar)
            }
            text = ns.replacingCharacters(in: match.range, with: replacement)
            ns = text as NSString
            matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        }
        return text
    }

    // MARK: 列表页

    static func videos(in html: String) -> [VideoItem] {
        guard let regex = makeRegex("href=\"(?:https?://[^\"/]*)?/videos/([a-zA-Z0-9_\\-]+)/\"") else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))

        var seen = Set<String>()
        var result: [VideoItem] = []
        result.reserveCapacity(matches.count)

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let slug = ns.substring(with: match.range(at: 1))
            guard seen.insert(slug).inserted else { continue }

            // 以锚点为中心取窗口：封面通常在链接前，标题在后
            let anchorStart = match.range.location
            let start = max(0, anchorStart - 700)
            let end = min(ns.length, NSMaxRange(match.range) + 1100)
            guard end > start else { continue }
            let window = ns.substring(with: NSRange(location: start, length: end - start))

            let cover = extractCover(from: window)

            var title = firstMatch(
                "<h6[^>]*class=\"[^\"]*title[^\"]*\"[^>]*>\\s*(?:<a[^>]*>)?(.*?)</",
                in: window
            ) ?? firstMatch("(?:title|alt)=\"([^\"]{3,200})\"", in: window) ?? ""

            title = decodeEntities(stripTags(title))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                title = slug.replacingOccurrences(of: "-", with: " ").uppercased()
            }

            let duration = firstMatch("(\\d{1,2}:\\d{2}(?::\\d{2})?)<", in: window) ?? ""

            result.append(VideoItem(
                id: slug,
                title: title,
                cover: cover,
                duration: duration,
                playPath: "/videos/\(slug)/"
            ))
        }
        return result
    }

    /// jable 的封面是懒加载，可能落在 data-src / data-original / srcset，
    /// 也可能没有扩展名、或是相对路径，逐级兜底。
    private static func extractCover(from window: String) -> String {
        let patterns = [
            "(?:data-src|data-original|data-lazy-src)=\"(https?://[^\"]+?\\.(?:jpe?g|png|webp)[^\"]*)\"",
            "(?:data-src|data-original|data-lazy-src)=\"(https?://[^\"]+)\"",
            "src=\"(https?://[^\"]+?\\.(?:jpe?g|png|webp)[^\"]*)\"",
            "srcset=\"([^\"\\s]+)"
        ]

        for pattern in patterns {
            guard let raw = firstMatch(pattern, in: window) else { continue }
            var value = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || value.hasPrefix("data:") { continue }
            if value.hasPrefix("//") {
                value = "https:" + value
            } else if value.hasPrefix("/") {
                value = Site.base + value
            }
            if value.hasPrefix("http") { return value }
        }
        return ""
    }

    /// 有些片源是 iframe 第三方播放器，页面里没有 m3u8，需要再抓一层
    static func iframeSource(in html: String) -> URL? {
        let patterns = [
            "<iframe[^>]+src=\"([^\"]+)\"",
            "player_url\\s*[:=]\\s*['\"]([^'\"]+)['\"]"
        ]
        for pattern in patterns {
            guard let raw = firstMatch(pattern, in: html) else { continue }
            var value = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("//") { value = "https:" + value }
            if value.hasPrefix("/") { value = Site.base + value }
            if let url = URL(string: value), url.scheme?.hasPrefix("http") == true {
                return url
            }
        }
        return nil
    }

    /// 列表页是否还有下一页
    static func hasNextPage(in html: String, currentPage: Int) -> Bool {
        let next = currentPage + 1
        return html.contains("?page=\(next)\"") || html.contains("/page/\(next)/")
    }

    // MARK: 详情 / 播放页

    static func detailTitle(in html: String) -> String? {
        if let raw = firstMatch("<h1[^>]*>(.*?)</h1>", in: html, group: 1) {
            let cleaned = decodeEntities(stripTags(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count > 2 { return cleaned }
        }
        if let raw = firstMatch("<title>(.*?)</title>", in: html, group: 1) {
            var cleaned = decodeEntities(stripTags(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
            for separator in [" | ", " - Jable", "- Jable", " Jable.TV"] {
                if let range = cleaned.range(of: separator) {
                    cleaned = String(cleaned[..<range.lowerBound])
                }
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    static func playSource(from html: String, fallbackTitle: String) -> PlaySource? {
        let candidates = [
            "hlsUrl\\s*[:=]\\s*['\"]([^'\"]+?\\.m3u8[^'\"]*)['\"]",
            "['\"](https?://[^'\"\\s]+?\\.m3u8[^'\"\\s]*)['\"]",
            "<source[^>]+src=\"([^\"]+?\\.m3u8[^\"]*)\"",
            "videoUrl\\s*[:=]\\s*['\"]([^'\"]+)['\"]"
        ]

        var raw: String?
        for pattern in candidates {
            if let found = firstMatch(pattern, in: html), !found.isEmpty {
                raw = found
                break
            }
        }
        guard var text = raw else { return nil }

        text = text.replacingOccurrences(of: "\\/", with: "/")
        text = decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }

        return PlaySource(title: detailTitle(in: html) ?? fallbackTitle, url: url)
    }
}
