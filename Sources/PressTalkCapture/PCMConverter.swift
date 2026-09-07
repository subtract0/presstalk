import AVFoundation

public enum CaptureError: Error, CustomStringConvertible {
    case failed(String)
    public var description: String {
        switch self { case .failed(let detail): return detail }
    }
}

/// One converter per press, used only on the capture consumer queue. Input is
/// the explicitly mapped device channel at its native rate; output is 16 kHz mono.
public final class PCMConverter {
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private var finished = false
    public private(set) var nativeFrames = 0
    public private(set) var outputFrames = 0

    public init(sampleRate: Double) throws {
        guard sampleRate.isFinite, (8000...384000).contains(sampleRate),
              let input = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: sampleRate, channels: 1, interleaved: false),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw CaptureError.failed("Unsupported microphone sample format.")
        }
        self.converter = converter
        inputFormat = input
        outputFormat = output
        converter.primeMethod = .normal
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    }

    public func append(_ samples: [Float]) throws -> [Float] {
        guard !finished, samples.allSatisfy(\.isFinite) else {
            throw CaptureError.failed("Invalid PCM or audio received after conversion ended.")
        }
        guard !samples.isEmpty else { return [] }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw CaptureError.failed("Could not allocate the microphone conversion buffer.")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        nativeFrames += samples.count
        return try convert(buffer, end: false)
    }

    public func finish() throws -> [Float] {
        guard !finished else { return [] }
        finished = true
        let tail = try convert(nil, end: true)
        let expected = Double(nativeFrames) * 16000 / inputFormat.sampleRate
        guard abs(Double(outputFrames) - expected) <= 2 else {
            throw CaptureError.failed("Microphone conversion lost audio (\(outputFrames) output frames, expected \(expected)).")
        }
        return tail
    }

    private func convert(_ input: AVAudioPCMBuffer?, end: Bool) throws -> [Float] {
        var supplied = false
        var result: [Float] = []
        // Input may be a long offline fixture; each pass is bounded separately.
        let maxPasses = max(32, Int(Double(input?.frameLength ?? 0) * 16000 / inputFormat.sampleRate / 4096) + 32)
        for _ in 0..<maxPasses {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else {
                throw CaptureError.failed("Could not allocate converted audio.")
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if let input, !supplied {
                    supplied = true
                    state.pointee = .haveData
                    return input
                }
                state.pointee = end ? .endOfStream : .noDataNow
                return nil
            }
            guard status != .error, error == nil else {
                throw CaptureError.failed("Microphone conversion failed: \(error?.localizedDescription ?? "unknown error")")
            }
            let count = Int(output.frameLength)
            if count > 0, let channel = output.floatChannelData?[0] {
                let chunk = Array(UnsafeBufferPointer(start: channel, count: count))
                guard chunk.allSatisfy(\.isFinite) else { throw CaptureError.failed("Non-finite converted PCM.") }
                result += chunk
                outputFrames += count
            }
            if status == .endOfStream || (!end && status == .inputRanDry) { return result }
            if count == 0 { throw CaptureError.failed("Microphone converter stopped making progress.") }
        }
        throw CaptureError.failed("Microphone converter exceeded its drain bound.")
    }
}
