import CoreAudio
import Foundation
import PressTalkCapture

func devices() throws -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    guard status == noErr, size > 0 else { throw CaptureError.failed("Cannot enumerate CoreAudio devices: status=\(status), bytes=\(size)") }
    var result = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &result) == noErr else {
        throw CaptureError.failed("Device enumeration failed.")
    }
    return result
}
func defaultInput() -> UInt32? {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0, size: UInt32 = 4
    return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value) == noErr ? value : nil
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2, let device = UInt32(arguments[1]) else {
        for id in try devices() { print("device=\(id) uid=\((try? HALCapture.uid(id)) ?? "unavailable") default=\(defaultInput() == id)") }
        print("Usage: presstalk-capture-probe DEVICE_ID [SECONDS] [CHANNEL_ZERO_BASED]")
        exit(2)
    }
    let seconds = arguments.count > 2 ? Double(arguments[2]) ?? 2 : 2
    guard seconds.isFinite, seconds > 0, seconds <= 600 else { throw CaptureError.failed("Invalid duration.") }
    let channel = arguments.count > 3 ? UInt32(arguments[3]) ?? 0 : 0
    let before = defaultInput()
    let capture = HALCapture()
    let lock = NSLock()
    var sum = 0.0, peak: Float = 0
    var sampleCount = 0
    try capture.start(session: 1, deviceID: device, deviceUID: HALCapture.uid(device), channel: channel,
        onSamples: { samples in
            lock.lock(); defer { lock.unlock() }
            sampleCount += samples.count
            for sample in samples { sum += Double(sample) * Double(sample); peak = max(peak, abs(sample)) }
        }, onFailure: { message in fputs("Capture failed: \(message)\n", stderr) })
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    guard let receipt = capture.stop(session: 1) else { throw CaptureError.failed("Missing capture receipt.") }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    print(String(decoding: try encoder.encode(receipt), as: UTF8.self))
    lock.lock()
    print("content samples=\(sampleCount) rms=\(sampleCount > 0 ? sqrt(sum / Double(sampleCount)) : 0) peak=\(peak)")
    lock.unlock()
    let after = defaultInput()
    print("default_before=\(before.map(String.init) ?? "unknown") default_after=\(after.map(String.init) ?? "unknown")")
    // This is a transport measurement, never a full dictation acceptance gate.
    exit(receipt.complete && sampleCount > 0 && sampleCount == receipt.convertedFrames && before != nil && before == after ? 0 : 1)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
