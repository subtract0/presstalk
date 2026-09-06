import Foundation

/// Remembers whether the current audio input is safe to tap, so the check does
/// not run on every keypress.
///
/// The preflight exists because `installTapOnBus` raises an Objective-C
/// exception that Swift cannot catch, and it killed the app three times in six
/// days. It answers by building a throwaway `AVAudioEngine` and reading the
/// input node's format -- measured on studio1 at 52.7 ms median and 187 ms at
/// worst, against a total press-to-capture cost of 130 ms. It was 40% of the
/// audio lost off the front of every dictation, and 22% of captures were losing
/// more than 0.2 s, which is a whole short first word in German.
///
/// The answer only changes when the audio hardware changes. So it is cached
/// against a fingerprint of the device, and any change to that fingerprint --
/// a different device, a different sample rate, a different channel count --
/// discards the cache and runs the real check again. Getting this wrong
/// reintroduces a crash rather than a slow start, so the fingerprint is
/// deliberately conservative: anything unrecognised counts as a change.
public struct AudioPreflightCache {

    /// Cheap CoreAudio properties, none of which require building an engine.
    public struct DeviceFingerprint: Equatable {
        public let deviceUID: String
        public let sampleRate: Double
        public let channelCount: UInt32

        public init(deviceUID: String, sampleRate: Double, channelCount: UInt32) {
            self.deviceUID = deviceUID
            self.sampleRate = sampleRate
            self.channelCount = channelCount
        }
    }

    private var cachedFingerprint: DeviceFingerprint?
    private var cachedFailure: String??

    public init() {}

    /// Returns the cached preflight result, or nil when the caller must run the
    /// real check. A cached result is only returned for an exactly matching
    /// fingerprint.
    ///
    /// The double optional is deliberate: the outer level is "do we know", the
    /// inner is "was there a failure". Collapsing them would make a cached
    /// success indistinguishable from a cache miss, and the app would either
    /// re-run the check forever or skip it when it should not.
    public func cachedResult(for fingerprint: DeviceFingerprint) -> String?? {
        guard let cachedFingerprint, cachedFingerprint == fingerprint,
              let cachedFailure else { return nil }
        return cachedFailure
    }

    public mutating func record(_ failure: String?, for fingerprint: DeviceFingerprint) {
        cachedFingerprint = fingerprint
        cachedFailure = failure
    }

    /// Forgets everything. Used when the device list changes in a way the
    /// fingerprint cannot describe, where re-running the check is the only safe
    /// answer.
    public mutating func invalidate() {
        cachedFingerprint = nil
        cachedFailure = nil
    }

    public var isPrimed: Bool { cachedFingerprint != nil }
}
