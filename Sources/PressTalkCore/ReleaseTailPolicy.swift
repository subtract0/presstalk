import Foundation

/// Decides when to stop recording after the trigger key is released.
///
/// The old rule was "wait at least 0.10 s, then stop as soon as the most recent
/// 0.10 s of audio looks quiet". Measured across 1,516 real captures on this
/// machine, it exited at the 0.10 s minimum essentially every time, with a
/// recent RMS around 0.0005 -- far below the 0.011 threshold. It was not
/// detecting the end of speech. It was detecting that the audio pipeline is
/// behind.
///
/// An input tap hands over buffers late: the samples available at the instant
/// of release describe audio from a hundred-odd milliseconds earlier. So the
/// window the old rule inspected was not the end of the sentence -- it was
/// whatever came before it, and after a deliberate pause mid-hold, that is
/// silence. The check said "quiet, stop now", the tap was torn down, and the
/// audio still in flight -- the final short sentence the user had just spoken
/// -- was discarded. Every capture in the log lost 0.1 to 0.15 s at the end
/// this way. On a trailing consonant nobody notices. On "Bis Donnerstag" after
/// a pause, the whole clause disappears.
///
/// The fix is to stop asking how quiet it sounds and start asking whether the
/// recording has caught up with the key. Silence only means the end of speech
/// once the audio actually reaches the moment of release.
public enum ReleaseTailPolicy {

    public struct Inputs {
        /// Wall-clock since the key was released.
        public let elapsedSeconds: Double
        /// Seconds of audio captured so far.
        public let capturedSeconds: Double
        /// Seconds of audio that should exist by the release moment: how long
        /// the key was held, less the time the engine took to start.
        public let expectedAtReleaseSeconds: Double
        /// RMS of the most recently delivered window.
        public let recentRMS: Double
        /// How long the captured length has stood still. A single poll seeing
        /// no growth means nothing: the tap hands over one buffer per 0.1 s
        /// while the loop polls every 0.025 s, so three polls in four
        /// legitimately see no new samples. Only a gap materially longer than
        /// one buffer says the tap has stopped delivering.
        public let secondsSinceCapturedGrew: Double

        public init(elapsedSeconds: Double, capturedSeconds: Double,
                    expectedAtReleaseSeconds: Double, recentRMS: Double,
                    secondsSinceCapturedGrew: Double) {
            self.elapsedSeconds = elapsedSeconds
            self.capturedSeconds = capturedSeconds
            self.expectedAtReleaseSeconds = expectedAtReleaseSeconds
            self.recentRMS = recentRMS
            self.secondsSinceCapturedGrew = secondsSinceCapturedGrew
        }
    }

    public enum Decision: Equatable {
        case keepWaiting(reason: String)
        case stop(reason: String)

        public var shouldStop: Bool { if case .stop = self { return true }; return false }
        public var reason: String {
            switch self {
            case .keepWaiting(let r), .stop(let r): return r
            }
        }
    }

    public static let minimumSeconds = 0.10
    public static let silenceRMSThreshold = 0.011
    /// How far behind the release moment the recording may still be before it
    /// counts as caught up. One tap buffer's worth of slack, so a capture that
    /// will never quite converge does not hold the tail open to its maximum.
    public static let catchUpToleranceSeconds = 0.05
    /// How long the capture may stand still before the tap counts as dead.
    ///
    /// Two and a half buffers. WhisperKit installs its tap with a 0.1 s buffer
    /// (`minBufferLength`), so at a 0.025 s poll interval the common case is
    /// three consecutive polls with no growth, entirely normally. The previous
    /// rule stopped on the FIRST of those, which is why 11 of 13 tails in the
    /// trace ended as `no_further_audio` while still 90-280 ms behind the key
    /// release -- the end of the sentence, thrown away as a dead stream.
    public static let stalledStreamSeconds = 0.25

    public static func decide(_ input: Inputs, maximumSeconds: Double) -> Decision {
        if input.elapsedSeconds >= maximumSeconds {
            return .stop(reason: "max_tail")
        }
        if input.elapsedSeconds < minimumSeconds {
            return .keepWaiting(reason: "below_minimum")
        }

        let behind = input.expectedAtReleaseSeconds - input.capturedSeconds
        if behind > catchUpToleranceSeconds {
            // The recording has not yet reached the moment the key came up, so
            // whatever the last window sounds like, it is not the end of what
            // was said. Stopping here is what removed the final sentence.
            //
            // Unless nothing is arriving any more: then waiting cannot help and
            // holding on only adds latency to a capture that is already broken.
            return input.secondsSinceCapturedGrew >= stalledStreamSeconds
                ? .stop(reason: "no_further_audio")
                : .keepWaiting(reason: "audio_still_in_flight")
        }

        if input.recentRMS <= silenceRMSThreshold {
            return .stop(reason: "silence_after_catch_up")
        }
        return .keepWaiting(reason: "still_speaking")
    }
}
