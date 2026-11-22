import Foundation

/// 站点没有开放 JSON 接口，全部靠 HTML 解析。
/// 解析规则集中在这里，模板一改只需要动这个文件。
enum Parser {

    // MARK: - 基础工具

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

    // MARK: - 列表页

    /// 列表页 / 搜索页里的卡片。返回去重后的条目。
    static func videos(in html: String) -> [VideoItem] {
        let marker = "<div class=\"video-item\">"
        let chunks = html.components(separatedBy: marker)
        guard chunks.count > 1 else { return [] }

        let hrefPattern = "href=\"(/index\\.php/vod/play/id/(\\d+)/sid/\\d+/nid/\\d+\\.html)\""
        var seen = Set<String>()
        var result: [VideoItem] = []
        result.reserveCapacity(chunks.count)

        for chunk in chunks.dropFirst() {
            guard let playPath = firstMatch(hrefPattern, in: chunk, group: 1),
                  let vodId = firstMatch(hrefPattern, in: chunk, group: 2),
                  seen.insert(vodId).inserted
            else { continue }

            let cover = firstMatch("data-original=\"([^\"]+)\"", in: chunk)
                ?? firstMatch("<img[^>]+src=\"([^\"]+)\"", in: chunk)
                ?? ""
            let title = decodeEntities(firstMatch("alt=\"([^\"]*)\"", in: chunk) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = decodeEntities(firstMatch("class=\"model-view\">([^<]*)<", in: chunk) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if title.isEmpty { continue }
            result.append(VideoItem(id: vodId, title: title, cover: cover, duration: duration, playPath: playPath))
        }
        return result
    }

    // MARK: - 播放页

    static func detailTitle(in html: String) -> String? {
        if let raw = firstMatch("<title>\\s*在线播放\\s*-\\s*(.*?)\\s*-\\s*KanAV", in: html, group: 1) {
            let cleaned = decodeEntities(stripTags(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        if let raw = firstMatch("<h1[^>]*>(.*?)</h1>", in: html, group: 1) {
            let cleaned = decodeEntities(stripTags(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    /// 苹果 CMS 的 player_aaaa：encrypt=2 时是 unescape(base64(url))，1 时是 unescape(url)。
    static func playSource(from html: String, fallbackTitle: String) -> PlaySource? {
        guard let json = firstMatch("var player_aaaa\\s*=\\s*(\\{.*?\\})\\s*</script>", in: html, group: 1),
              let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        var raw = (object["url"] as? String) ?? ""
        guard !raw.isEmpty else { return nil }

        let encrypt: String
        if let value = object["encrypt"] {
            encrypt = String(describing: value)
        } else {
            encrypt = "0"
        }

        if encrypt == "2" {
            raw = base64Decode(raw) ?? raw
        }
        if let decoded = raw.removingPercentEncoding {
            raw = decoded
        }
        raw = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }

        return PlaySource(title: detailTitle(in: html) ?? fallbackTitle, url: url)
    }

    static func base64Decode(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "-", with: "+")
        text = text.replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder > 0 {
            text += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
