import AVFoundation
import Combine

/// 实时字幕：音频管线 → 语音识别 → 翻译 → 字幕。
/// 全部在端上完成（iOS 17.4+），低版本可用自建在线翻译接口兜底。
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
    @Published var showTranslation = true

    /// ja-JP / zh-CN / en-US
    var sourceLanguage = "ja-JP"

    private weak var engine: PlayerEngine?
    private var processor: AudioTapProcessor?
    private var speech: SpeechRecognizerService?
    private var pendingSource = ""
    private var translateWork: Task<Void, Never>?
    private var flushWork: DispatchWorkItem?

    // MARK: 开关

    func toggle(engine: PlayerEngine) async {
        if isRunning {
            stop()
        } else {
            await start(engine: engine)
        }
    }

    func start(engine: PlayerEngine) async {
        guard !isRunning else { return }
        self.engine = engine
        status = "准备中…"

        let authorized = await SpeechRecognizerService.requestAuthorization()
        guard authorized else {
            status = "没有语音识别权限，去设置里开启"
            return
        }

        guard let speech = SpeechRecognizerService(
            languageCode: sourceLanguage,
            onSegment: { [weak self] text in
                self?.handle(text)
            },
            onError: { [weak self] message in
                self?.status = message
            }
        ) else {
            status = "当前设备不支持 \(sourceLanguage) 端上识别"
            return
        }
        self.speech = speech

        guard let trackID = await engine.primaryAudioTrackID() else {
            status = "没有可用的音频轨"
            return
        }

        let processor = AudioTapProcessor { [weak self] buffer in
            self?.speech?.append(buffer)
        }
        guard let tap = processor.makeTap() else {
            status = "音频管线接入失败"
            return
        }
        self.processor = processor

        engine.installAudioMix(trackID: trackID, tap: tap)
        speech.start()
        isRunning = true
        status = "实时字幕已开启"
    }

    func stop() {
        speech?.stop()
        speech = nil
        engine?.removeAudioMix()
        engine = nil
        processor = nil
        translateWork?.cancel()
        translateWork = nil
        flushWork?.cancel()
        flushWork = nil
        pendingSource = ""
        liveCaption = nil
        isRunning = false
        status = "已关闭"
    }

    // MARK: 识别片段 -> 字幕

    private func handle(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pendingSource += trimmed
        if pendingSource.count > 90 {
            pendingSource = String(pendingSource.suffix(90))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
