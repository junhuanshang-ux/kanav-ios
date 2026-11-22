import Foundation

/// whisper.cpp 模型：首次使用时下载到 Documents，之后离线可用。
/// 默认 base-q5_1（约 57 MB，速度/质量平衡）；手机端跑 small 以上会明显掉帧。
final class WhisperModelStore: NSObject, ObservableObject {

    static let shared = WhisperModelStore()

    static let fileName = "ggml-base-q5_1.bin"
    static let remote = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin")!
    static let approximateSize = "约 57 MB"

    @Published private(set) var progress: Double = 0
    @Published private(set) var isDownloading = false
    @Published private(set) var errorText: String?
    @Published private(set) var revision = 0

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    private override init() {
        super.init()
    }

    var localURL: URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent(Self.fileName)
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localURL.path)
    }

    var sizeText: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path),
              let size = attributes[.size] as? NSNumber
        else { return Self.approximateSize }
        return String(format: "%.0f MB", size.doubleValue / 1024 / 1024)
    }

    // MARK: 下载 / 删除

    func download() {
        guard !isDownloading else { return }
        isDownloading = true
        errorText = nil
        progress = 0

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.session = session

        let task = session.downloadTask(with: Self.remote)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        isDownloading = false
    }

    func removeModel() {
        cancel()
        try? FileManager.default.removeItem(at: localURL)
        progress = 0
        revision += 1
    }
}

extension WhisperModelStore: URLSessionDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let destination = localURL
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            progress = 1
            isDownloading = false
            errorText = nil
            revision += 1
        } catch {
            isDownloading = false
            errorText = error.localizedDescription
        }
        session.finishTasksAndInvalidate()
        self.session = nil
        task = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        isDownloading = false
        errorText = error.localizedDescription
    }
}
