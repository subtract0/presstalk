import AVFoundation
import Foundation
import PressTalkCore

/// Records a short burst from the default input and reports what actually
/// arrived. See `AudioCaptureProbeReport` for why the permission API alone is
/// not evidence.
enum AudioCaptureProbe {
    static func run(durationSeconds: Double = 1.2) -> AudioCaptureProbeReport {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let statusName: String
        switch status {
        case .notDetermined: statusName = "notDetermined"
        case .restricted: statusName = "restricted"
        case .denied: statusName = "denied"
        case .authorized: statusName = "authorized"
        @unknown default: statusName = "unknown"
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        let hasInputDevice = format.sampleRate > 0 && format.channelCount > 0

        guard hasInputDevice else {
            return AudioCaptureProbeReport(
                outcome: .noInputDevice,
                authorizationStatus: statusName,
                sampleRate: format.sampleRate,
                channelCount: format.channelCount,
                framesCaptured: 0,
                peakAmplitude: 0,
                durationSeconds: 0,
                detail: "input node reports sampleRate=\(format.sampleRate) channels=\(format.channelCount)"
            )
        }

        let counter = FrameCounter()
        // installTapOnBus raises an ObjC exception rather than throwing, so the
        // format has to be sound before we get here. It is: we just read it off
        // the same node.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            counter.add(buffer: buffer)
        }
        defer { input.removeTap(onBus: 0) }

        var engineStarted = true
        var detail = ""
        do {
            try engine.start()
        } catch {
            engineStarted = false
            detail = "\(error)"
        }

        if engineStarted {
            Thread.sleep(forTimeInterval: durationSeconds)
            engine.stop()
        }

        let (frames, peak) = counter.snapshot()
        let outcome = AudioCaptureProbeReport.classify(
            engineStarted: engineStarted,
            hasInputDevice: hasInputDevice,
            framesCaptured: frames
        )
        if outcome == .silentDenial {
            detail = "engine started and delivered no frames in \(durationSeconds)s; "
                + "check that the app is signed with com.apple.security.device.audio-input"
        }

        return AudioCaptureProbeReport(
            outcome: outcome,
            authorizationStatus: statusName,
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            framesCaptured: frames,
            peakAmplitude: peak,
            durationSeconds: engineStarted ? durationSeconds : 0,
            detail: detail
        )
    }

    /// `--audio-selftest` prints one JSON object and exits. It runs inside the
    /// app's own bundle, so it inherits the identity, entitlements, and TCC
    /// grant the real dictation path uses -- which is the whole point.
    static func runCommandLineSelfTestIfRequested(_ arguments: [String]) {
        guard arguments.contains("--audio-selftest") else { return }
        let report = run()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        exit(report.isUsable ? 0 : 1)
    }
}

/// Tap callbacks arrive on a real-time audio thread, so the accumulator is
/// lock-guarded rather than a plain var.
private final class FrameCounter {
    private let lock = NSLock()
    private var frames = 0
    private var peak: Float = 0

    func add(buffer: AVAudioPCMBuffer) {
        var localPeak: Float = 0
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) {
                localPeak = max(localPeak, abs(channel[index]))
            }
        }
        lock.lock()
        frames += Int(buffer.frameLength)
        peak = max(peak, localPeak)
        lock.unlock()
    }

    func snapshot() -> (Int, Float) {
        lock.lock()
        defer { lock.unlock() }
        return (frames, peak)
    }
}
