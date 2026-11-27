import Foundation
import WebKit

/// 清缓存。注意：**不能清 cookie**，否则 Cloudflare 的 cf_clearance 会失效，
/// 下次打开要重新做人机验证。
enum CacheCleaner {

    struct Result {
        let freedBytes: Int64
        let description: String
    }

    static func clear() async -> Result {
        var freed: Int64 = 0

        // 1. 图片内存缓存
        ImageLoader.shared.clearCache()

        // 2. 播放地址缓存
        PlayURLCache.shared.clear()

        // 3. URLSession 磁盘/内存缓存
        let cached = Int64(URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage)
        URLCache.shared.removeAllCachedResponses()
        freed += cached

        // 4. WebKit 的缓存（只清缓存类型，保留 cookies / localStorage）
        let store = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: types, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }

        // 5. 临时目录里遗留的分片文件
        let temp = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files where file.pathExtension == "ts" || file.lastPathComponent.hasPrefix("kanav-") {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    freed += Int64(size)
                }
                try? FileManager.default.removeItem(at: file)
            }
        }

        let text: String
        if freed >= 1024 * 1024 {
            text = String(format: "已清理 %.1f MB", Double(freed) / 1024 / 1024)
        } else if freed >= 1024 {
            text = String(format: "已清理 %.0f KB", Double(freed) / 1024)
        } else {
            text = "已清理缓存"
        }
        return Result(freedBytes: freed, description: text)
    }
}
