import Foundation

/// 标题转中文，两条路：
///   1. 纯汉字（站点大量标题是繁体）→ 系统内置 `Traditional-Simplified` 直接转，零延迟零网络
///   2. 含假名（日文）→ MyMemory 翻译（免费无需 key），Google 仅作兜底
///
/// 之前只打 Google，而三个端点全部 429 限流，所以一条都没翻出来。
final class TitleTranslator: ObservableObject {

    static let shared = TitleTranslator()

    /// 缓存变化计数器，卡片监听它刷新
    @Published private(set) var version = 0

    private var cache: [String: String] = [:]
    private var failed: Set<String> = []
    private var pending: Set<String> = []
    private var queue: [String] = []
    private var active = 0
    private let maxConcurrent = 1

    private init() {}

    func translated(_ text: String) -> String? {
        cache[text]
    }

    /// 列表卡片出现时调用
    func request(_ text: String) {
        guard !text.isEmpty, cache[text] == nil, !failed.contains(text), !pending.contains(text) else {
            return
        }

        // 没有假名 = 中文（多半是繁体），本地转简体即可
        if !Self.containsJapanese(text) {
            let simplified = Self.traditionalToSimplified(text)
            if !simplified.isEmpty, simplified != text {
                cache[text] = simplified
                version += 1
            }
            return
        }

        pending.insert(text)
        queue.append(text)
        pump()
    }

    private func pump() {
        while active < maxConcurrent, !queue.isEmpty {
            let text = queue.removeFirst()
            active += 1
            Task { [weak self] in
                let result = await Self.fetch(text)
                await MainActor.run {
                    guard let self = self else { return }
                    self.active -= 1
                    self.pending.remove(text)
                    if let result = result, !result.isEmpty, result != text {
                        self.cache[text] = result
                        self.version += 1
                    } else {
                        // 失败就别再反复打，避免继续被限流
                        self.failed.insert(text)
                    }
                    self.pump()
                }
            }
        }
    }

    // MARK: 本地繁转简

    private static func traditionalToSimplified(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return mutable as String
    }

    private static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
        }
    }

    // MARK: 网络翻译

    private static func fetch(_ text: String) async -> String? {
        if let result = await myMemory(text) { return result }
        if let result = await google(text) { return result }
        return nil
    }

    private static func myMemory(_ text: String) async -> String? {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "ja|zh-CN")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["responseData"] as? [String: Any],
              let translated = payload["translatedText"] as? String
        else { return nil }

        let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        // 额度用完时它会把警告塞进译文里
        if trimmed.isEmpty || trimmed.uppercased().contains("MYMEMORY WARNING") { return nil }
        return trimmed
    }

    private static func google(_ text: String) async -> String? {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "zh-CN"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://jable.tv/", forHTTPHeaderField: "Referer")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = json.first as? [Any]
        else { return nil }

        var result = ""
        for segment in segments {
            if let parts = segment as? [Any], let piece = parts.first as? String {
                result += piece
            }
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
