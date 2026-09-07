import AVFoundation
import CoreAudio
import Foundation
import PressTalkCore
import PressTalkCapture

/// A transport check using the production capture adapter. This proves retained
/// PCM, not speech recognition or insertion into a target application.
enum AudioCaptureProbe {
    static func run(durationSeconds: Double = 1.2, deviceID: AudioDeviceID? = nil) -> AudioCaptureProbeReport {
        let authorization = String(describing: AVCaptureDevice.authorizationStatus(for: .audio))
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = deviceID ?? 0
        var size: UInt32 = 4
        if deviceID == nil {
            let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
            if status != noErr { device = 0 }
        }
        let capture = HALCapture()
        let lock = NSLock()
        var frames = 0
        var peak: Float = 0
        var detail = ""
        var receipt: CaptureReceipt?
        do {
            guard device != 0 else { throw CaptureError.failed("No CoreAudio input device is available.") }
            try capture.start(session: 1, deviceID: device, deviceUID: HALCapture.uid(device),
                onSamples: { samples in
                    lock.lock(); defer { lock.unlock() }
                    frames += samples.count
                    peak = max(peak, samples.map { abs($0) }.max() ?? 0)
                }, onFailure: { _ in })
            let deadline = Date().addingTimeInterval(durationSeconds)
            while Date() < deadline {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            receipt = capture.stop(session: 1)
            detail = receipt?.failure ?? "AUHAL delivered and retained PCM; speech and insertion were not tested."
        } catch { detail = String(describing: error) }
        lock.lock(); defer { lock.unlock() }
        return AudioCaptureProbeReport(
            outcome: device == 0 ? .noInputDevice :
                (receipt?.complete == true && frames > 0 && frames == receipt?.convertedFrames ? .captured : .engineFailed),
            authorizationStatus: authorization, sampleRate: 16000,
            channelCount: 1, framesCaptured: frames, peakAmplitude: peak,
            durationSeconds: Double(frames) / 16000, detail: detail)
    }

    static func runCommandLineSelfTestIfRequested(_ arguments: [String]) {
        guard arguments.contains("--audio-selftest") else { return }
        var device: UInt32?
        if let index = arguments.firstIndex(of: "--audio-device"), index + 1 < arguments.count {
            guard let value = UInt32(arguments[index + 1]) else { exit(2) }
            device = value
        }
        let report = run(deviceID: device)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) { print(String(decoding: data, as: UTF8.self)) }
        exit(report.isUsable ? 0 : 1)
    }
}
