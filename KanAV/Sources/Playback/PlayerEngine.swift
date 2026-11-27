import AVFoundation
import AVKit
import UIKit

// MARK: - 播放状态

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case ended
    case failed(String)

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .loading, .buffering: return true
        default: return false
        }
    }
}

struct MediaTrackOption: Identifiable, Equatable {
    let id: String
    let title: String
    let option: AVMediaSelectionOption?

    static func == (lhs: MediaTrackOption, rhs: MediaTrackOption) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 播放引擎

/// 包装 AVPlayer：状态机、缓冲、进度、倍速、循环、画面比例、音轨/字幕轨。
/// 所有 @Published 更新都在主线程完成。
final class PlayerEngine: NSObject, ObservableObject {

    // 对外暴露给 AVPlayerLayer 使用
    let player = AVPlayer()

    @Published private(set) var state: PlaybackState = .idle {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
    }
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var bufferedTime: Double = 0
    @Published private(set) var presentationSize: CGSize = .zero
    @Published var speed: Double = 1.0
    @Published var isLooping = false
    @Published var gravity: AVLayerVideoGravity = .resizeAspect
    @Published private(set) var audioOptions: [MediaTrackOption] = []
    @Published private(set) var subtitleOptions: [MediaTrackOption] = []
    @Published private(set) var selectedAudioID: String?
    @Published private(set) var selectedSubtitleID: String?

    override init() {
        super.init()
        // 记住上次的倍速和画面比例
        if let saved = UserDefaults.standard.object(forKey: "player.speed") as? Double {
            speed = saved
        }
        if let raw = UserDefaults.standard.string(forKey: "player.gravity") {
            gravity = AVLayerVideoGravity(rawValue: raw)
        }
    }


    /// 上层页面拿播放状态
    var onStateChange: ((PlaybackState) -> Void)?
    /// 上层页面拿进度（当前秒, 总秒）
    var onProgress: ((Double, Double) -> Void)?

    private var item: AVPlayerItem?
    private var asset: AVURLAsset?
    private var timeObserver: Any?
    private var observers: [NSKeyValueObservation] = []
    private var tokens: [NSObjectProtocol] = []
    private var hasEnded = false

    // MARK: 生命周期

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        teardownObservers()
    }

    // MARK: 载入

    func load(url: URL, referer: String? = nil, userAgent: String? = nil, autoplay: Bool = true) {
        teardown()

        var headers: [String: String] = [
            "Referer": referer ?? (Site.base + "/"),
            "User-Agent": userAgent ?? Site.userAgent,
            "Accept": "*/*"
        ]
        if let cookie = Net.cookieHeader(for: url) {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        self.asset = asset

        let item = AVPlayerItem(asset: asset)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        // 倍速时保持音调不变（默认会变成「快放」的怪声）
        item.audioTimePitchAlgorithm = .spectral
        // 只攒 2 秒就起播：既快又不会因为缓冲太薄而频繁卡
        item.preferredForwardBufferDuration = 2
        self.item = item
        hasEnded = false
        player.replaceCurrentItem(with: item)
        // 保留默认的「等缓冲」策略：上一版改成 false 后起播快了但拖动/卡顿时会停住播不动
        player.automaticallyWaitsToMinimizeStalling = true

        observe(item: item)
        addTimeObserver()

        state = .loading
        loadMediaOptions(asset: asset, item: item)

        if autoplay {
            play()
        }
    }

    func unload() {
        pause()
        teardown()
        state = .idle
        currentTime = 0
        duration = 0
        bufferedTime = 0
    }

    // MARK: 播放控制

    func play() {
        guard item != nil else { return }
        if hasEnded {
            hasEnded = false
            seek(to: 0)
        }
        player.play()
        applySpeedIfNeeded()
        refreshState()
    }

    func pause() {
        player.pause()
        refreshState()
    }

    func togglePlay() {
        if state.isPlaying || player.timeControlStatus == .playing {
            pause()
        } else {
            play()
        }
    }

    /// 截取指定时间点的画面（用于保存到相册）
    func snapshot(at seconds: Double) async -> UIImage? {
        guard let asset = asset else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.4, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.4, preferredTimescale: 600)

        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, _ in
                if let image = image {
                    continuation.resume(returning: UIImage(cgImage: image))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func seek(to seconds: Double) {
        guard duration > 0 || item != nil else { return }

        // 记住 seek 前是不是在播，完成后再把播放状态还回去，
        // 否则 AVPlayer 会停在 paused（表现就是「拖一下就暂停」）
        let wasPlaying = player.timeControlStatus == .playing
        let clamped = max(0, min(seconds, max(duration - 0.15, 0)))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)

        player.seek(to: time, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentTime = clamped
                if finished, wasPlaying {
                    self.player.play()
                    self.applySpeedIfNeeded()
                    self.refreshState()
                }
            }
        }
        currentTime = clamped
    }

    func skip(_ delta: Double) {
        let base = currentTime
        seek(to: base + delta)
    }

    func setSpeed(_ value: Double) {
        UserDefaults.standard.set(value, forKey: "player.speed")
        speed = value
        applySpeedIfNeeded()
    }

    func toggleLoop() {
        isLooping.toggle()
    }

    func cycleGravity() {
        switch gravity {
        case .resizeAspect: gravity = .resizeAspectFill
        case .resizeAspectFill: gravity = .resize
        default: gravity = .resizeAspect
        }
        UserDefaults.standard.set(gravity.rawValue, forKey: "player.gravity")
    }

    func gravityTitle() -> String {
        switch gravity {
        case .resizeAspect: return "适应"
        case .resizeAspectFill: return "铺满"
        case .resize: return "拉伸"
        default: return "适应"
        }
    }

    // MARK: 音轨 / 字幕

    func selectAudio(_ option: MediaTrackOption) {
        guard let item = item, let asset = asset else { return }
        guard let group = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        item.select(option.option, in: group)
        selectedAudioID = option.id
    }

    func selectSubtitle(_ option: MediaTrackOption?) {
        guard let item = item, let asset = asset else { return }
        guard let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        item.select(option?.option, in: group)
        selectedSubtitleID = option?.id
    }

    // MARK: 内部

    private func applySpeedIfNeeded() {
        if speed == 1.0 { return }
        guard player.timeControlStatus == .playing else { return }
        player.rate = Float(speed)
    }

    private func addTimeObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                self.currentTime = seconds
            }
            self.onProgress?(self.currentTime, self.duration)
        }
    }

    private func observe(item: AVPlayerItem) {
        observers.append(item.observe(\.status, options: [.new, .initial]) { [weak self] observed, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if observed.status == .readyToPlay {
                    let seconds = observed.duration.seconds
                    if seconds.isFinite, seconds > 0 {
                        self.duration = seconds
                    }
                }
                self.refreshState()
            }
        })

        observers.append(item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshState() }
        })

        observers.append(item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshState() }
        })

        observers.append(item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] observed, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let range = observed.loadedTimeRanges.last?.timeRangeValue {
                    let end = range.start.seconds + range.duration.seconds
                    if end.isFinite {
                        self.bufferedTime = end
                    }
                }
            }
        })

        observers.append(item.observe(\.presentationSize, options: [.new]) { [weak self] observed, _ in
            DispatchQueue.main.async {
                self?.presentationSize = observed.presentationSize
            }
        })

        observers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshState() }
        })

        tokens.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.hasEnded = true
            if self.isLooping {
                self.hasEnded = false
                self.seek(to: 0)
                self.player.play()
                self.applySpeedIfNeeded()
                self.state = .playing
            } else {
                self.state = .ended
            }
        })

        tokens.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.state = .failed(error?.localizedDescription ?? "播放中断")
        })

        tokens.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.state.isPlaying {
                self.state = .buffering
            }
        })
    }

    private func refreshState() {
        guard let item = item else {
            state = .idle
            return
        }

        if case .failed = state { return }
        if let error = item.error ?? player.error {
            state = .failed(error.localizedDescription)
            return
        }

        switch item.status {
        case .unknown:
            state = .loading
        case .readyToPlay:
            let seconds = item.duration.seconds
            if seconds.isFinite, seconds > 0 {
                duration = seconds
            }
            if item.isPlaybackBufferEmpty && player.timeControlStatus != .paused {
                state = .buffering
            } else if player.timeControlStatus == .playing {
                state = hasEnded ? .ended : .playing
            } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                state = .buffering
            } else {
                state = hasEnded ? .ended : .paused
            }
        case .failed:
            state = .failed(item.error?.localizedDescription ?? "播放失败")
        @unknown default:
            state = .idle
        }
    }

    private func loadMediaOptions(asset: AVURLAsset, item: AVPlayerItem) {
        Task { [weak self] in
            let characteristics = (try? await asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions)) ?? []
            var audio: [MediaTrackOption] = []
            var subtitles: [MediaTrackOption] = []

            for characteristic in characteristics {
                guard let group = asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else { continue }
                let mapped = group.options.map {
                    MediaTrackOption(id: $0.displayName, title: $0.displayName, option: $0)
                }
                if characteristic == .audible {
                    audio = mapped
                } else if characteristic == .legible {
                    subtitles = mapped
                }
            }

            let currentAudio = asset.mediaSelectionGroup(forMediaCharacteristic: .audible).flatMap {
                item.currentMediaSelection.selectedMediaOption(in: $0)
            }?.displayName
            let currentSubtitle = asset.mediaSelectionGroup(forMediaCharacteristic: .legible).flatMap {
                item.currentMediaSelection.selectedMediaOption(in: $0)
            }?.displayName

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.audioOptions = audio
                self.subtitleOptions = subtitles
                self.selectedAudioID = currentAudio ?? audio.first?.id
                self.selectedSubtitleID = currentSubtitle
            }
        }
    }

    private func teardownObservers() {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
    }

    private func teardown() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        teardownObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        item = nil
        asset = nil
        audioOptions = []
        subtitleOptions = []
        selectedAudioID = nil
        selectedSubtitleID = nil
    }
}
