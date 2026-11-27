import AVFoundation
import Foundation

/// HLS 请求代理。
///
/// 为什么需要它：`AVURLAssetHTTPHeaderFieldsKey` 只保证主 playlist 请求带 header，
/// 分片（.ts）和密钥请求是 AVPlayer 内部发的，不一定带 Referer / Cookie，
/// CDN 一校验就 403 —— 表现就是"有的片子能播、有的片一直转圈"。
///
/// 做法：把 asset 的 URL 换成自定义 scheme（kanavstream://），
/// 由本类接管全部请求，统一加 UA / Referer / Cookie，
/// 并且把 playlist 里的分片地址也改写成代理地址，保证分片同样走这里。
final class StreamProxyLoader: NSObject, AVAssetResourceLoaderDelegate {

    static let scheme = "kanavstream"

    private let referer: String
    private let userAgent: String
    private let cookie: String?
    private let session: URLSession

    init(referer: String, userAgent: String, cookie: String?) {
        self.referer = referer
        self.userAgent = userAgent
        self.cookie = cookie

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .useProtocolCachePolicy
        self.session = URLSession(configuration: config)

        super.init()
    }

    // MARK: URL 转换

    static func proxyURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = scheme
        return components.url ?? url
    }

    static func realURL(from proxyURL: URL) -> URL? {
        guard var components = URLComponents(url: proxyURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        return components.url
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url,
              let realURL = Self.realURL(from: url)
        else { return false }

        // 已经取消或完成的请求：宣称已接管但什么都不做。
        // 这里绝不能 return false —— 对自定义 scheme 返回 false 会让 AVFoundation 自己兜底并可能崩溃。
        if loadingRequest.isCancelled || loadingRequest.isFinished {
            return true
        }

        var request = URLRequest(url: realURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let cookie = cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        var start: Int64 = 0
        var length: Int64 = 0
        if let dataRequest = loadingRequest.dataRequest {
            start = dataRequest.requestedOffset
            length = Int64(dataRequest.requestedLength)
            if start > 0 || length > 0 {
                let end = length > 0 ? String(start + length - 1) : ""
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
            }
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            autoreleasepool {
                guard let self = self else { return }
                // 已经被 AVPlayer 取消/完成的请求不能再碰，否则会崩
                guard !loadingRequest.isCancelled, !loadingRequest.isFinished else { return }

                if let error = error {
                    loadingRequest.finishLoading(with: error)
                    return
                }
                guard let http = response as? HTTPURLResponse, let payload = data else {
                    loadingRequest.finishLoading(with: NSError(domain: "StreamProxy", code: -1))
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    loadingRequest.finishLoading(with: NSError(
                        domain: "StreamProxy",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "播放源返回 \(http.statusCode)"]
                    ))
                    return
                }

                // playlist：改写分片地址，让后续请求也走这里
                if start == 0,
                   let text = String(data: payload, encoding: .utf8),
                   text.contains("#EXTM3U") {
                    let rewritten = self.rewritePlaylist(text, base: realURL)
                    let body = Data(rewritten.utf8)
                    loadingRequest.dataRequest?.respond(with: body)
                    if let info = loadingRequest.contentInformationRequest {
                        info.contentType = "application/vnd.apple.mpegurl"
                        info.contentLength = Int64(body.count)
                        info.isByteRangeAccessSupported = false
                    }
                    loadingRequest.finishLoading()
                    return
                }

                // 分片：必须只回填 AVPlayer 要的那一段。
                // 服务端有时会忽略 Range 直接返回 200 全量，整包塞回去会让 AVPlayer 越界崩溃。
                var slice = payload
                if let dataRequest = loadingRequest.dataRequest {
                    let offset = max(0, dataRequest.requestedOffset)
                    let length = dataRequest.requestedLength
                    if http.statusCode == 200, length > 0, payload.count > length {
                        let lower = min(Int(offset), payload.count)
                        let upper = min(payload.count, lower + length)
                        if lower < upper {
                            slice = payload.subdata(in: lower..<upper)
                        }
                    }
                    dataRequest.respond(with: slice)
                }

                if let info = loadingRequest.contentInformationRequest {
                    info.contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
                    info.contentLength = Int64(slice.count)
                    info.isByteRangeAccessSupported = true
                }
                loadingRequest.finishLoading()
            }
        }
        task.resume()
        return true
    }

    // MARK: playlist 重写

    private func rewritePlaylist(_ text: String, base: URL) -> String {
        var output: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                output.append(rawLine)
                continue
            }

            if line.hasPrefix("#") {
                output.append(rewriteTagURI(line, base: base))
                continue
            }

            if let absolute = URL(string: line, relativeTo: base)?.absoluteURL {
                output.append(proxyString(absolute))
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    /// 处理 #EXT-X-KEY / #EXT-X-MAP 里的 URI="..."
    private func rewriteTagURI(_ line: String, base: URL) -> String {
        guard line.contains("URI=\"") else { return line }
        guard let range = line.range(of: "URI=\"") else { return line }

        let prefix = String(line[..<range.upperBound])
        let rest = String(line[range.upperBound...])
        guard let closing = rest.firstIndex(of: "\"") else { return line }

        let rawURI = String(rest[..<closing])
        let suffix = String(rest[closing...])

        guard let absolute = URL(string: rawURI, relativeTo: base)?.absoluteURL else { return line }
        return prefix + proxyString(absolute) + suffix
    }

    private func proxyString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = Self.scheme
        return components.url?.absoluteString ?? url.absoluteString
    }
}
