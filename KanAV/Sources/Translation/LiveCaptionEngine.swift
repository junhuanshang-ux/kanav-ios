import AVFoundation
import Combine

/// 实时字幕：优先 whisper.cpp 本地推理，模型缺失时回退系统识别。
/// 音频来自 HLSAudioSource（按分片自己解码 PCM），完全不依赖 AVPlayer 的音频管线。
final class LiveCaptionEngine: ObservableObject {

    struct Caption: Identifiable, Equatable {
        let id = UUID()
        let source: String
        let target: String
    }

    @Published private(set) var liveCaption: Caption?
    @Published private(set) var history: [Caption] = []
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    @Published private(set) var engineName = ""
    @Published var showTranslation = true

    /// ja-JP / zh-CN / en-US
    var sourceLanguage = "ja-JP"

    private static let chunkSamples = 16000 * 4

    private var audioSource: HLSAudioSource?
    private var speech: SpeechRecognizerService?
    private var whisper: WhisperEngine?

    private let audioQueue = DispatchQueue(label: "kanav.caption.audio", qos: .userInitiated)
    private var pendingSamples: [Float] = []
    private var isTranscribing = false

    private let speechFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )

    private var pendingSource = ""
    private var translateWork: Task<Void, Never>?
    private var flushWork: DispatchWorkItem?

    private var whisperLanguageCode: String {
        sourceLanguage.split(separator: "-").first.map(String.init) ?? "ja"
    }

    // MARK: 开关

    func toggle(streamURL: URL?, fromSeconds: Double) async {
        if isRunning {
            stop()
            return
        }
        guard let url = streamURL else {
            status = "还没解析到播放地址"
            return
        }
        await start(streamURL: url, fromSeconds: fromSeconds)
    }

    func start(streamURL: URL, fromSeconds: Double) async {
        guard !isRunning else { return }
        status = "准备中…"

        if await prepareWhisper() {
            engineName = "Whisper.cpp"
        } else if await prepareSpeech() {
            engineName = "系统识别"
        } else {
            return
        }

        let source = HLSAudioSource(playlistURL: streamURL)
        audioSource = source
        source.start(fromSeconds: fromSeconds) { [weak self] samples in
            self?.consume(samples)
        }

        isRunning = true
        if whisper != nil {
            status = "Whisper 实时字幕已开启（延迟约 10 秒）"
        } else {
            speech?.start()
            status = "实时字幕已开启（系统识别兜底）"
        }
    }

    func stop() {
        audioSource?.stop()
        audioSource = nil
        speech?.stop()
        speech = nil
        whisper = nil

        audioQueue.async { [weak self] in
            self?.pendingSamples.removeAll()
            self?.isTranscribing = false
        }

        translateWork?.cancel()
        translateWork = nil
        flushWork?.cancel()
        flushWork = nil
        pendingSource = ""
        liveCaption = nil
        isRunning = false
        engineName = ""
        status = "已关闭"
    }

    // MARK: 引擎准备

    private func prepareWhisper() async -> Bool {
        guard WhisperEngine.isSupported else { return false }
        let store = WhisperModelStore.shared
        guard store.isDownloaded else {
            status = "Whisper 模型未下载"
            return false
        }

        let path = store.localURL.path
        let code = whisperLanguageCode
        let engine: WhisperEngine? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: WhisperEngine(modelPath: path, language: code))
            }
        }
        guard let engine = engine else {
            status = "Whisper 模型加载失败"
            return false
        }
        whisper = engine
        return true
    }

    private func prepareSpeech() async -> Bool {
        let authorized = await SpeechRecognizerService.requestAuthorization()
        guard authorized else {
            status = "没有语音识别权限，可先下载 Whisper 模型"
            return false
        }
        guard let service = SpeechRecognizerService(
            languageCode: sourceLanguage,
            onSegment: { [weak self] segment in self?.handle(segment.text) },
            onError: { [weak self] message in self?.status = message }
        ) else {
            status = "当前设备不支持 \(sourceLanguage) 识别"
            return false
        }
        speech = service
        return true
    }

    // MARK: 音频 -> 文本

    private func consume(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        audioQueue.async { [weak self] in
            guard let self = self else { return }

            if self.whisper != nil {
                self.pendingSamples.append(contentsOf: samples)
                if self.pendingSamples.count >= Self.chunkSamples, !self.isTranscribing {
                    self.drainAndTranscribe()
                }
            } else {
                self.feedSpeech(samples)
            }
        }
    }

    private func feedSpeech(_ samples: [Float]) {
        guard let format = speechFormat else { return }
        let frames = AVAudioFrameCount(samples.count)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                channel.update(from: base, count: samples.count)
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.speech?.append(buffer)
        }
    }

    private func drainAndTranscribe() {
        guard let whisper = whisper else { return }
        let take = min(pendingSamples.count, Self.chunkSamples)
        let slice = Array(pendingSamples.prefix(take))
        pendingSamples.removeFirst(take)
        isTranscribing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = whisper.transcribe(slice) ?? ""
            guard let self = self else { return }
            self.audioQueue.async {
                self.isTranscribing = false
                if !text.isEmpty {
                    DispatchQueue.main.async {
                        self.handle(text)
                    }
                }
            }
        }
    }

    // MARK: 文本 -> 字幕

    private func handle(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pendingSource += trimmed
        if pendingSource.count > 120 {
            pendingSource = String(pendingSource.suffix(120))
        }

        scheduleTranslate()
        scheduleFlush()
    }

    private func scheduleTranslate() {
        translateWork?.cancel()
        let snapshot = pendingSource
        translateWork = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }

            let translated = await Translator.shared.translate(snapshot)
            await MainActor.run {
                guard let self = self else { return }
                self.liveCaption = Caption(source: snapshot, target: translated ?? "")
            }
        }
    }

    private func scheduleFlush() {
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let caption = self.liveCaption, !caption.source.isEmpty {
                self.history.append(caption)
                if self.history.count > 40 {
                    self.history.removeFirst(self.history.count - 40)
                }
            }
            self.liveCaption = nil
            self.pendingSource = ""
        }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
    }
}
