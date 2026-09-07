import AudioToolbox
import CoreAudio
import Foundation
import PressTalkHAL

public struct CaptureReceipt: Codable {
    public var session: UInt64
    public var deviceUID: String
    public var deviceID: UInt32
    public var boundDeviceID: UInt32 = 0
    public var defaultInputBefore: UInt32?
    public var defaultInputAfter: UInt32?
    public var channel: UInt32
    public var channels: UInt32 = 0
    public var nativeRate: Double = 0
    public var maximumFrames: UInt32 = 0
    public var callbacks: UInt64 = 0
    public var renderedFrames: UInt64 = 0
    public var retainedFrames: UInt64 = 0
    public var consumedFrames: UInt64 = 0
    public var convertedFrames: Int = 0
    public var droppedFrames: UInt64 = 0
    public var firstPCMSeconds: Double?
    public var firstConvertedSeconds: Double?
    public var stopSeconds: Double?
    public var failure: String?
    public var complete: Bool = false
}

/// Owns one AUHAL per press. All control, conversion and delivery runs on one
/// serial queue. The HAL callback is C: preallocated buffers and SPSC atomics,
/// no Swift ARC, allocation, locks, logging, dispatch, conversion or UI.
public final class HALCapture {
    private let queue = DispatchQueue(label: "app.presstalk.capture", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var context: OpaquePointer?
    private var converter: PCMConverter?
    private var timer: DispatchSourceTimer?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var receipt: CaptureReceipt?
    private var onSamples: (([Float]) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var onReceipt: ((CaptureReceipt) -> Void)?
    private var scratch: [Float] = []
    private var requestedAt = 0.0
    private var lastValidationAt = 0.0
    private var poisoned = false
    private var closedThrough: UInt64 = 0

    public init() { queue.setSpecific(key: queueKey, value: 1) }
    deinit {
        if DispatchQueue.getSpecific(key: queueKey) == 1 { _ = finishLocked() }
        else { queue.sync { _ = finishLocked() } }
    }

    public func start(session: UInt64, deviceID: AudioDeviceID, deviceUID: String,
                      channel: UInt32 = 0, onSamples: @escaping ([Float]) -> Void,
                      onReceipt: ((CaptureReceipt) -> Void)? = nil,
                      onFailure: @escaping (String) -> Void) throws {
        try queue.sync {
            guard session > closedThrough, context == nil, !poisoned else { throw CaptureError.failed("The microphone session was cancelled or has not stopped.") }
            receipt = CaptureReceipt(session: session, deviceUID: deviceUID, deviceID: deviceID, channel: channel)
            receipt?.defaultInputBefore = Self.defaultInputID()
            self.onSamples = onSamples
            self.onFailure = onFailure
            self.onReceipt = onReceipt
            requestedAt = pt_now()
            do {
                guard !deviceUID.isEmpty, try Self.uid(deviceID) == deviceUID else {
                    throw CaptureError.failed("The selected microphone is no longer available. Select it again.")
                }
                // Install before opening: setup changes cannot hide between the
                // initial device read and capture. Stale queued blocks check session.
                for (selector, scope) in [
                    (kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
                    (kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal),
                    (kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
                ] {
                    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                              mElement: kAudioObjectPropertyElementMain)
                    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                        guard let self, self.receipt?.session == session, self.context != nil else { return }
                        self.failLocked("The microphone configuration changed during this recording. Nothing was inserted.")
                    }
                    let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, queue, block)
                    guard status == noErr else { throw CaptureError.failed("Could not monitor the microphone (\(status)).") }
                    listeners.append((address, block))
                }
                var status: OSStatus = noErr
                guard let opened = pt_create(deviceID, channel, &status) else {
                    throw CaptureError.failed("Could not open the selected microphone (\(status)).")
                }
                context = opened
                let stats = pt_stats(opened)
                converter = try PCMConverter(sampleRate: stats.sampleRate)
                scratch = [Float](repeating: 0, count: Int(stats.maximumFrames))
                guard pt_start(opened) == noErr else { throw CaptureError.failed("The selected microphone could not start.") }
                // Reads the actual binding/format again before retaining any PCM.
                try validateDeviceLocked()
                timer = DispatchSource.makeTimerSource(queue: queue)
                timer?.setEventHandler { [weak self] in self?.pollLocked() }
                timer?.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
                timer?.resume()
            } catch {
                receipt?.failure = String(describing: error)
                _ = finishLocked()
                throw error
            }
        }
    }

    /// Idempotent and session-scoped: a stale task cannot stop a later press.
    public func stop(session: UInt64) -> CaptureReceipt? {
        queue.sync {
            closedThrough = max(closedThrough, session)
            guard receipt?.session == session else { return nil }
            return finishLocked()
        }
    }

    public func invalidate(session: UInt64, reason: String) {
        queue.async { [weak self] in
            guard let self, self.receipt?.session == session, self.context != nil else { return }
            self.failLocked(reason)
        }
    }

    private func pollLocked() {
        guard let context else { return }
        do {
            if pt_now() - lastValidationAt >= 0.1 { try validateDeviceLocked() }
            let stats = pt_stats(context)
            let now = pt_now()
            if (stats.firstPCMAt == 0 && now - requestedAt > 2) ||
                (stats.firstPCMAt > 0 && stats.firstPCMAt - requestedAt > 2) {
                throw CaptureError.failed("No audio arrived from the selected microphone within two seconds.")
            }
            try drainLocked()
            let stallBound = max(0.5, 5 * Double(stats.maximumFrames) / stats.sampleRate)
            if stats.firstPCMAt > 0 && now - stats.lastPCMAt > stallBound {
                throw CaptureError.failed("The microphone stopped delivering audio. Nothing was inserted.")
            }
            if stats.retainedFrames > UInt64(stats.sampleRate * 600) {
                throw CaptureError.failed("The recording reached the ten-minute limit. Nothing was inserted.")
            }
        } catch { failLocked(String(describing: error)) }
    }

    private func drainLocked() throws {
        guard let context, let converter else { return }
        // At most the queue capacity per tick; producer cannot monopolize control.
        for _ in 0..<64 {
            let stats = pt_stats(context)
            guard stats.failure == 0 else {
                throw CaptureError.failed("Microphone capture interrupted (reason \(stats.failure), status \(stats.status)). Nothing was inserted.")
            }
            let count = scratch.withUnsafeMutableBufferPointer { pt_read(context, $0.baseAddress, UInt32($0.count)) }
            if count == 0 { return }
            let converted = try converter.append(Array(scratch.prefix(Int(count))))
            deliverLocked(converted)
        }
    }

    private func deliverLocked(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        if receipt?.firstConvertedSeconds == nil { receipt?.firstConvertedSeconds = pt_now() - requestedAt }
        onSamples?(samples)
    }

    private func recordFailure(_ reason: String) {
        if receipt?.failure == nil { receipt?.failure = reason }
    }

    private func failLocked(_ reason: String) {
        guard context != nil else { return }
        recordFailure(reason)
        let callback = onFailure
        _ = finishLocked()
        callback?(reason)
    }

    private func finishLocked() -> CaptureReceipt? {
        timer?.cancel(); timer = nil
        guard context != nil || !listeners.isEmpty || converter != nil else {
            onSamples = nil; onFailure = nil
            emitReceiptLocked()
            return receipt
        }
        let started = pt_now()
        if let context {
            let beforeStop = pt_stats(context)
            if beforeStop.firstPCMAt > 0 && started - beforeStop.lastPCMAt > 0.2 {
                recordFailure("Audio stopped before the recording ended. Nothing was inserted.")
            }
            if pt_stop(context) != noErr { receipt?.failure = "The microphone could not stop safely." }
            do {
                try validateDeviceLocked()
                if receipt?.failure == nil { try drainLocked() }
                if receipt?.failure == nil, let converter { deliverLocked(try converter.finish()) }
            } catch { recordFailure(String(describing: error)) }
            let stats = pt_stats(context)
            receipt?.boundDeviceID = stats.boundDevice
            receipt?.nativeRate = stats.sampleRate
            receipt?.channels = stats.channels
            receipt?.maximumFrames = stats.maximumFrames
            receipt?.callbacks = stats.callbacks
            receipt?.renderedFrames = stats.renderedFrames
            receipt?.retainedFrames = stats.retainedFrames
            receipt?.consumedFrames = stats.consumedFrames
            receipt?.convertedFrames = converter?.outputFrames ?? 0
            receipt?.droppedFrames = stats.droppedFrames
            if stats.firstPCMAt > 0 { receipt?.firstPCMSeconds = stats.firstPCMAt - requestedAt }
            if stats.failure != 0 { recordFailure("Capture failure \(stats.failure), status \(stats.status).") }
            if stats.retainedFrames == 0 { recordFailure("No audio arrived from the selected microphone.") }
            if stats.retainedFrames != stats.consumedFrames { recordFailure("Microphone audio was not fully consumed.") }
            if !pt_destroy(context) {
                poisoned = true
                receipt?.failure = "Microphone teardown failed. Restart PressTalk before recording again."
            }
            self.context = nil
            receipt?.stopSeconds = pt_now() - started
        }
        if let device = receipt?.deviceID {
            for (var address, block) in listeners {
                let status = AudioObjectRemovePropertyListenerBlock(device, &address, queue, block)
                if status != noErr { receipt?.failure = "Could not remove the microphone monitor (\(status))." }
            }
        }
        listeners.removeAll()
        receipt?.defaultInputAfter = Self.defaultInputID()
        let complete = receipt?.failure == nil && (receipt?.convertedFrames ?? 0) > 0
        receipt?.complete = complete
        converter = nil; onSamples = nil; onFailure = nil
        emitReceiptLocked()
        return receipt
    }

    private func emitReceiptLocked() {
        let callback = onReceipt
        onReceipt = nil
        if let receipt { callback?(receipt) }
    }

    private func validateDeviceLocked() throws {
        guard let context, let receipt else { return }
        let stats = pt_stats(context)
        guard pt_validate(context) == noErr else {
            throw CaptureError.failed("The microphone binding or format changed. Nothing was inserted.")
        }
        guard try Self.uid(receipt.deviceID) == receipt.deviceUID else {
            throw CaptureError.failed("The selected microphone disconnected. Nothing was inserted.")
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        var rate = 0.0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(receipt.deviceID, &address, 0, nil, &size, &rate) == noErr,
              rate == stats.sampleRate else {
            throw CaptureError.failed("The microphone sample rate changed. Nothing was inserted.")
        }
        lastValidationAt = pt_now()
    }

    public static func uid(_ device: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw CaptureError.failed("The selected microphone is unavailable (\(status)).") }
        return value as String
    }

    private static func defaultInputID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &value)
        return status == noErr && value != 0 ? value : nil
    }
}
