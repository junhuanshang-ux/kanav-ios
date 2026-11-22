import AVFoundation
import Foundation

/// HLS 音频源：把 m3u8 的分片下下来自己解码。
///
/// 为什么不挂 MTAudioProcessingTap：
/// 站点用的是单条媒体播放列表（`#EXTINF + xxx.ts`，TS 里音视频复用），
/// AVFoundation 不为它暴露独立音频轨，`audioMix` 在 HLS 上也本身不生效，
/// 所以拿不到 PCM。这里按分片顺序下载 → AVAssetReader 解成 16kHz 单声道，
/// 与 AVPlayer 播放管线解耦。
final class HLSAudioSource {

    private struct Segment {
        let url: URL
        let start: Double
        let duration: Double
    }

    /// 阶段回调（已在主线程外，调用方自己切主线程）
    var onStage: ((String) -> Void)?

    private let playlistURL: URL
    private var isRunning = false
    private var task: Task<Void, Never>?

    init(playlistURL: URL) {
        self.playlistURL = playlistURL
    }

    func start(fromSeconds: Double, onSamples: @escaping ([Float]) -> Void) {
        stop()
        isRunning = true
        // detached：绝不能继承调用方的 MainActor，否则解码会把界面卡死
        task = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.run(fromSeconds: fromSeconds, onSamples: onSamples)
        }
    }

    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
    }

    // MARK: 主循环

    private func run(fromSeconds: Double, onSamples: @escaping ([Float]) -> Void) async {
        onStage?("读取播放列表…")
        guard let segments = await loadPlaylist(), !segments.isEmpty else {
            onStage?("播放列表解析失败")
            return
        }
        onStage?("共 \(segments.count) 个分片，准备解码")

        var index = segments.firstIndex { $0.start + $0.duration > fromSeconds } ?? 0
        var decodedSeconds = 0.0
        var failures = 0

        while isRunning, index < segments.count {
            if Task.isCancelled { return }
            let segment = segments[index]
            index += 1

            guard let local = await download(segment.url) else {
                failures += 1
                onStage?(failures >= 3 ? "分片下载失败（网络或防盗链）" : "重试下载…")
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }

            let samples = await decode(local)
            try? FileManager.default.removeItem(at: local)

            if Task.isCancelled { return }

            if samples.isEmpty {
                failures += 1
                onStage?(failures >= 3 ? "分片解码失败（TS 里没解出音频）" : "换下一个分片…")
                continue
            }

            failures = 0
            decodedSeconds += Double(samples.count) / 16000.0
            onStage?(String(format: "已解码 %.0f 秒，识别中…", decodedSeconds))
            onSamples(samples)

            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    // MARK: m3u8

    private func loadPlaylist() async -> [Segment]? {
        var request = URLRequest(url: playlistURL)
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Site.base + "/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 20

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        var segments: [Segment] = []
        var cursor = 0.0
        var pendingDuration = 0.0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF:") {
                let value = line.dropFirst(8).split(separator: ",").first.map(String.init) ?? "0"
                pendingDuration = Double(value.trimmingCharacters(in: .whitespaces)) ?? 0
            } else if !line.isEmpty, !line.hasPrefix("#") {
                guard let url = URL(string: line, relativeTo: playlistURL)?.absoluteURL else { continue }
                segments.append(Segment(url: url, start: cursor, duration: pendingDuration))
                cursor += pendingDuration
                pendingDuration = 0
            }
        }
        return segments.isEmpty ? nil : segments
    }

    // MARK: 下载

    private func download(_ url: URL) async -> URL? {
        var request = URLRequest(url: url)
        request.setValue(Site.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Site.base + "/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 20

        do {
            let (temp, _) = try await URLSession.shared.download(for: request)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("ts")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    // MARK: 解码

    /// 先按 16k 单声道请求；部分 TS 不支持直接重采样时退回原始采样率再手动降。
    private func decode(_ fileURL: URL) async -> [Float] {
        let asset = AVURLAsset(url: fileURL)

        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty else {
            return []
        }
        let track = tracks[0]

        if let samples = read(track: track, asset: asset, sampleRate: 16000), !samples.isEmpty {
            return samples
        }
        // 兜底：按原始格式取，再线性重采样到 16k
        if let raw = read(track: track, asset: asset, sampleRate: nil), !raw.isEmpty {
            return raw
        }
        return []
    }

    private func read(track: AVAssetTrack, asset: AVURLAsset, sampleRate: Double?) -> [Float]? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }

        var settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1
        ]
        if let rate = sampleRate {
            settings[AVSampleRateKey] = rate
        }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        reader.startReading()

        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            var buffer = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            buffer.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
            }
            samples.append(contentsOf: buffer)
        }
        let status = reader.status
        reader.cancelReading()

        guard status != .failed else { return nil }

        guard sampleRate == nil else { return samples }
        return resampleTo16k(samples, sourceRate: Double(track.naturalTimeScale) > 0 ? estimateRate(asset: asset) : 48000)
    }

    private func estimateRate(asset: AVURLAsset) -> Double {
        // 拿不到精确采样率时按 48k 处理，whisper 对 ±音高误差容忍度还可以
        48000
    }

    private func resampleTo16k(_ samples: [Float], sourceRate: Double) -> [Float] {
        guard sourceRate > 0, abs(sourceRate - 16000) > 1 else { return samples }
        let ratio = 16000.0 / sourceRate
        let count = Int(Double(samples.count) * ratio)
        guard count > 0 else { return [] }

        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let position = Double(index) / ratio
            let lower = Int(position)
            let upper = min(lower + 1, samples.count - 1)
            guard lower < samples.count else { break }
            let fraction = Float(position - Double(lower))
            output[index] = samples[lower] * (1 - fraction) + samples[upper] * fraction
        }
        return output
    }
}
