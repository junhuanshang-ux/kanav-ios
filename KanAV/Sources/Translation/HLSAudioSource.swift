import AVFoundation
import Foundation

/// HLS 音频源：把 m3u8 的分片下下来自己解码。
///
/// 为什么不挂 MTAudioProcessingTap：
/// 站点用的是单条媒体播放列表（`#EXTINF + xxx.ts`，TS 里音视频复用），
/// AVFoundation 不会为它暴露独立音频轨，`audioMix` 在 HLS 上本身也不生效，
/// 所以拿不到 PCM。这里改成按分片顺序下载 → AVAssetReader 解成 16kHz 单声道，
/// 与 AVPlayer 的播放管线解耦，字幕会滞后几秒但稳定可跑。
final class HLSAudioSource {

    private struct Segment {
        let url: URL
        let start: Double
        let duration: Double
    }

    private let playlistURL: URL
    private var isRunning = false
    private var task: Task<Void, Never>?

    init(playlistURL: URL) {
        self.playlistURL = playlistURL
    }

    func start(fromSeconds: Double, onSamples: @escaping ([Float]) -> Void) {
        stop()
        isRunning = true
        task = Task { [weak self] in
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
        guard let segments = await loadPlaylist(), !segments.isEmpty else { return }

        var index = segments.firstIndex { $0.start + $0.duration > fromSeconds } ?? 0

        while isRunning, index < segments.count {
            if Task.isCancelled { return }
            let segment = segments[index]
            index += 1

            guard let local = await download(segment.url) else {
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            }
            let samples = await decode(local)
            try? FileManager.default.removeItem(at: local)

            if Task.isCancelled { return }
            if !samples.isEmpty {
                onSamples(samples)
            }
            // 让出一点时间，避免一口气把整部片子的分片全扒下来
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    // MARK: m3u8

    private func loadPlaylist() async -> [Segment]? {
        guard let data = try? Data(contentsOf: playlistURL),
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
        return segments
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

    private func decode(_ fileURL: URL) async -> [Float] {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset)
        else { return [] }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
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
        reader.cancelReading()
        return samples
    }
}
