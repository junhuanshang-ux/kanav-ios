import Foundation

/// 标题翻译：把日文片名转成简体中文。
///
/// 走 Google 的 gtx 端点（无需 key），并发限 2、结果常驻内存，
/// 翻译失败的条目直接显示原文，不影响列表。
final class TitleTranslator: ObservableObject {

    static let shared = TitleTranslator()

    /// 缓存变化计数器，卡片监听它刷新
    @Published private(set) var version = 0

    private var cache: [String: String] = [:]
    private var pending: Set<String> = []
    private var queue: [String] = []
    private var active = 0
    private let maxConcurrent = 2

    private init() {}

    func translated(_ text: String) -> String? {
        cache[text]
    }

    /// 列表卡片出现时调用，翻译结果回来后自动刷新
    func request(_ text: String) {
        guard !text.isEmpty, cache[text] == nil, !pending.contains(text) else { return }
        guard containsJapanese(text) else { return }
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
                    }
                    self.pump()
                }
            }
        }
    }

    /// 含平假名/片假名才翻（纯中文标题不用翻）
    private func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
        }
    }

    private static func fetch(_ text: String) async -> String? {
        let endpoints = [
            "https://translate.googleapis.com/translate_a/single",
            "https://translate.google.com/translate_a/single",
            "https://clients5.google.com/translate_a/single"
        ]

        for endpoint in endpoints {
            guard var components = URLComponents(string: endpoint) else { continue }
            components.queryItems = [
                URLQueryItem(name: "client", value: "gtx"),
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: "zh-CN"),
                URLQueryItem(name: "dt", value: "t"),
                URLQueryItem(name: "q", value: text)
            ]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://jable.tv/", forHTTPHeaderField: "Referer")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let segments = json.first as? [Any]
            else { continue }

            var result = ""
            for segment in segments {
                if let parts = segment as? [Any], let piece = parts.first as? String {
                    result += piece
                }
            }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
