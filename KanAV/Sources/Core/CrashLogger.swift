import Foundation

/// 崩溃现场记录。侧载 App 拿不到 Xcode 的崩溃日志，
/// 这里把 NSException 和常见信号写到 Documents，重进 App 后可以导出。
enum CrashLogger {

    static var logURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("kanav-crash.log")
    }

    static var hasLog: Bool {
        FileManager.default.fileExists(atPath: logURL.path)
    }

    static var logText: String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    }

    private static var logPathPointer: UnsafeMutablePointer<CChar>?
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        logPathPointer = strdup(logURL.path)

        NSSetUncaughtExceptionHandler { exception in
            let header = "EXCEPTION \(exception.name.rawValue)\n\(exception.reason ?? "-")\n"
            let stack = exception.callStackSymbols.joined(separator: "\n")
            append("\(header)\(stack)\n")
        }

        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig) { value in
                if let pointer = logPathPointer, let file = fopen(pointer, "a") {
                    fputs("SIGNAL \(value)\n", file)
                    fclose(file)
                }
                exit(value)
            }
        }
    }

    static func append(_ text: String) {
        let payload = "---- \(ISO8601DateFormatter().string(from: Date())) ----\n\(text)\n"
        let data = Data(payload.utf8)

        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: logURL)
    }
}
