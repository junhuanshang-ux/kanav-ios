import AVFoundation
import Speech

/// 流式语音识别：拿 PCM 片段直接喂 SFSpeechAudioBufferRecognitionRequest。
/// 走 on-device 优先，识别任务约 1 分钟会被系统掐断，这里自动续。
final class SpeechRecognizerService {

    struct Segment {
        let text: String
        let isFinal: Bool
    }

    private let recognizer: SFSpeechRecognizer?
    private let onSegment: (Segment) -> Void
    private let onError: (String) -> Void

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var lastText = ""

    private(set) var isRunning = false
    private let languageCode: String

    init?(
        languageCode: String,
        onSegment: @escaping (Segment) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)),
              recognizer.isAvailable
        else {
            return nil
        }
        self.languageCode = languageCode
        self.recognizer = recognizer
        self.onSegment = onSegment
        self.onError = onError
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func start() {
        guard !isRunning, let recognizer = recognizer else { return }
        isRunning = true
        lastText = ""
        beginTask(recognizer: recognizer)
        scheduleRestart()
    }

    func stop() {
        isRunning = false
        restartTimer?.invalidate()
        restartTimer = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        lastText = ""
    }

    /// 音频线程调用
    func append(_ buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        request?.append(buffer)
    }

    // MARK: 内部

    private func beginTask(recognizer: SFSpeechRecognizer) {
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            newRequest.requiresOnDeviceRecognition = true
        }
        request = newRequest

        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty, text != self.lastText {
                    let appended = Self.delta(previous: self.lastText, current: text)
                    self.lastText = text
                    if !appended.isEmpty {
                        let segment = Segment(text: appended, isFinal: result.isFinal)
                        DispatchQueue.main.async { self.onSegment(segment) }
                    }
                }
                if result.isFinal {
                    self.rotate()
                }
            }

            if let error = error {
                let message = error.localizedDescription
                DispatchQueue.main.async { self.onError(message) }
                self.rotate()
            }
        }
    }

    /// 识别任务到时限就换一条，避免「识别已停止」
    private func scheduleRestart() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            self?.rotate()
        }
    }

    private func rotate() {
        guard isRunning, let recognizer = recognizer else { return }
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        lastText = ""
        beginTask(recognizer: recognizer)
    }

    private static func delta(previous: String, current: String) -> String {
        if previous.isEmpty { return current }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count)).trimmingCharacters(in: .whitespaces)
        }
        return current
    }
}
