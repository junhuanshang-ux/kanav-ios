import AVFoundation
import MediaToolbox

/// 用 MTAudioProcessingTap 在播放管线上抓取解码后的 PCM，喂给语音识别。
/// 不额外起一路播放、不占带宽，音画同步。
final class AudioTapProcessor {

    private let onSamples: (AVAudioPCMBuffer) -> Void
    private var format: AVAudioFormat?

    init(onSamples: @escaping (AVAudioPCMBuffer) -> Void) {
        self.onSamples = onSamples
    }

    // MARK: 创建

    func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: audioTapInit,
            finalize: audioTapFinalize,
            prepare: audioTapPrepare,
            unprepare: audioTapUnprepare,
            process: audioTapProcess
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        return status == noErr ? tap : nil
    }

    // MARK: 回调（音频线程）

    fileprivate func prepare(processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
        format = AVAudioFormat(streamDescription: processingFormat)
    }

    fileprivate func unprepare() {
        format = nil
    }

    fileprivate func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frames: CMItemCount) {
        guard let format = format, frames > 0 else { return }
        let sources = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)

        let targets = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for index in 0..<min(sources.count, targets.count) {
            guard let source = sources[index].mData, let target = targets[index].mData else { continue }
            let bytes = min(Int(sources[index].mDataByteSize), Int(targets[index].mDataByteSize))
            if bytes > 0 {
                memcpy(target, source, bytes)
            }
        }
        onSamples(buffer)
    }
}

// MARK: - C 回调桥接

private func audioTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func audioTapFinalize(_ tap: MTAudioProcessingTap) {
    // clientInfo 由 ARC 持有，这里不释放
}

private func audioTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let processor = Unmanaged<AudioTapProcessor>.fromOpaque(storage).takeUnretainedValue()
    processor.prepare(processingFormat: processingFormat)
}

private func audioTapUnprepare(_ tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let processor = Unmanaged<AudioTapProcessor>.fromOpaque(storage).takeUnretainedValue()
    processor.unprepare()
}

private func audioTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
    )
    guard status == noErr else { return }

    let storage = MTAudioProcessingTapGetStorage(tap)
    let processor = Unmanaged<AudioTapProcessor>.fromOpaque(storage).takeUnretainedValue()
    processor.process(bufferList: bufferListInOut, frames: numberFramesOut.pointee)
}
