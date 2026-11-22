import AVFoundation
import Foundation

#if canImport(whisper)
import whisper
#endif

/// whisper.cpp 本地推理封装。
/// 模型文件由 WhisperModelStore 下载到 Documents，运行时按 4 秒切片喂进来。
final class WhisperEngine {

    private var context: OpaquePointer?
    private let language: String

    /// 当前构建是否链接了 whisper.cpp
    static var isSupported: Bool {
        #if canImport(whisper)
        return true
        #else
        return false
        #endif
    }

    init?(modelPath: String, language: String) {
        self.language = language

        #if canImport(whisper)
        // 先试 Metal（快），失败再退回纯 CPU，避免 GPU 初始化失败就整个不可用
        if let created = Self.makeContext(modelPath: modelPath, useGPU: true) {
            context = created
        } else if let created = Self.makeContext(modelPath: modelPath, useGPU: false) {
            context = created
        } else {
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(whisper)
    private static func makeContext(modelPath: String, useGPU: Bool) -> OpaquePointer? {
        var params = whisper_context_default_params()
        params.use_gpu = useGPU
        return modelPath.withCString { pointer in
            whisper_init_from_file_with_params(pointer, params)
        }
    }
    #endif

    deinit {
        #if canImport(whisper)
        if let context = context {
            whisper_free(context)
        }
        #endif
    }

    /// samples: 16kHz / 单声道 / Float32
    func transcribe(_ samples: [Float]) -> String? {
        #if canImport(whisper)
        guard let context = context, samples.count > 1600 else { return nil }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        params.suppress_blank = true
        params.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))

        let languagePointer = strdup(language)
        defer { free(languagePointer) }
        params.language = UnsafePointer(languagePointer)

        let status = samples.withUnsafeBufferPointer { buffer -> Int32 in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }
        guard status == 0 else { return nil }

        var text = ""
        let segmentCount = whisper_full_n_segments(context)
        if segmentCount > 0 {
            for index in 0..<segmentCount {
                if let pointer = whisper_full_get_segment_text(context, index) {
                    text += String(cString: pointer)
                }
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed

        #else
        return nil
        #endif
    }
}
