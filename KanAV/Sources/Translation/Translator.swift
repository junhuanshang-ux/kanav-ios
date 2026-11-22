import Foundation

#if canImport(Translation)
import Translation

/// 端上翻译（iOS 17.4+，Translation framework）。
/// TranslationSession 只能从 SwiftUI 的 .translationTask 里拿到，所以单独包一层。
@available(iOS 17.4, *)
final class SystemTranslationBridge {

    static let shared = SystemTranslationBridge()

    private var session: TranslationSession?

    private init() {}

    func attach(_ newSession: TranslationSession) {
        session = newSession
    }

    var isReady: Bool { session != nil }

    func translate(_ text: String) async -> String? {
        guard let session = session else { return nil }
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            return nil
        }
    }
}
#endif

/// 翻译门面：优先端上，失败再走自建在线接口（OpenAI 兼容）。
final class Translator {

    static let shared = Translator()

    struct RemoteConfig {
        let endpoint: URL
        let apiKey: String
        let model: String
    }

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: 在线兜底配置（UserDefaults，用户可以自己填）

    var remoteConfig: RemoteConfig? {
        guard let raw = defaults.string(forKey: "translate.endpoint"),
              let url = URL(string: raw),
              let key = defaults.string(forKey: "translate.key"),
              !key.isEmpty
        else { return nil }
        let model = defaults.string(forKey: "translate.model") ?? "gpt-4o-mini"
        return RemoteConfig(endpoint: url, apiKey: key, model: model)
    }

    var hasAnyBackend: Bool {
        if #available(iOS 17.4, *) {
            #if canImport(Translation)
            return true
            #endif
        }
        return remoteConfig != nil
    }

    // MARK: 翻译

    func translate(_ text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        #if canImport(Translation)
        if #available(iOS 17.4, *) {
            if let result = await SystemTranslationBridge.shared.translate(trimmed) {
                return result
            }
        }
        #endif

        if let remote = remoteConfig {
            return await translateRemotely(trimmed, config: remote)
        }
        return nil
    }

    private func translateRemotely(_ text: String, config: RemoteConfig) async -> String? {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": config.model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": "你是视频字幕翻译。把用户给的句子翻译成简体中文，只输出译文，不加解释和引号。"],
                ["role": "user", "content": text]
            ]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String
            else { return nil }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
