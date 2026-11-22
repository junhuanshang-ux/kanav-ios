import AVFoundation

/// 把播放管线抓到的 PCM 重采样成 whisper 需要的 16kHz / 单声道 / Float32。
final class AudioResampler {

    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    init?(sampleRate: Double = 16000) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }
        outputFormat = format
    }

    func convert(_ input: AVAudioPCMBuffer) -> [Float]? {
        if converter == nil || inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: outputFormat)
            inputFormat = input.format
        }
        guard let converter = converter else { return nil }

        let ratio = outputFormat.sampleRate / max(input.format.sampleRate, 1)
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 512
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else { return nil }

        var provided = false
        var conversionError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return input
        }

        converter.convert(to: output, error: &conversionError, withInputFrom: inputBlock)
        guard conversionError == nil,
              let channel = output.floatChannelData?[0],
              output.frameLength > 0
        else { return nil }

        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
