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
        /// False when a poll produced no new samples at all, which means the
        /// tap has gone quiet as a source rather than the room being quiet.
        public let capturedGrewSinceLastPoll: Bool

        public init(elapsedSeconds: Double, capturedSeconds: Double,
                    expectedAtReleaseSeconds: Double, recentRMS: Double,
                    capturedGrewSinceLastPoll: Bool) {
            self.elapsedSeconds = elapsedSeconds
            self.capturedSeconds = capturedSeconds
            self.expectedAtReleaseSeconds = expectedAtReleaseSeconds
            self.recentRMS = recentRMS
            self.capturedGrewSinceLastPoll = capturedGrewSinceLastPoll
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
            return input.capturedGrewSinceLastPoll
                ? .keepWaiting(reason: "audio_still_in_flight")
                : .stop(reason: "no_further_audio")
        }

        if input.recentRMS <= silenceRMSThreshold {
            return .stop(reason: "silence_after_catch_up")
        }
        return .keepWaiting(reason: "still_speaking")
    }
}
