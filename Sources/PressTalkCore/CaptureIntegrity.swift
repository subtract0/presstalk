import Foundation

/// Decides whether the audio that reached the recognizer can be trusted to be
/// what the user said.
///
/// Written after a real failure on 2026-09-06. The key was held for 37.2
/// seconds; 1.7 seconds of samples arrived and every one of them was zero. The
/// AirPods were the system default input, so PressTalk fell back to the USB
/// microphone and promoted it to default mid-flight; the engine took 1.66 s to
/// start against a device being reconfigured underneath it and then delivered
/// silence. Nothing noticed. The recognizer was handed 1.7 seconds of digital
/// silence and did what recognizers do with silence -- it invented words, and
/// the user got "you you" pasted into a chat.
///
/// The lesson is not about hallucination filtering. Filtering was already
/// there and it worked: it rejected "you". The lesson is that nobody compared
/// what was captured against what was asked for. A 95% shortfall between the
/// hold and the recording is a hardware or driver failure, and the honest
/// response is to say so, not to transcribe the wreckage.
public enum CaptureIntegrity {

    public enum Verdict: Equatable {
        /// The recording plausibly contains what was said.
        case usable
        /// Every sample was at or near zero. No microphone reached this app.
        case silent
        /// Far less audio arrived than the key was held for.
        case truncated(capturedSeconds: Double, heldSeconds: Double)

        public var isUsable: Bool { self == .usable }

        /// What to tell the person, in their terms. They pressed a key and
        /// spoke; the failure is not theirs and the message should not read
        /// like it is.
        public var userFacingMessage: String? {
            switch self {
            case .usable:
                return nil
            case .silent:
                return "No sound reached PressTalk. Check that the right "
                    + "microphone is selected and not muted, then try again."
            case .truncated(let captured, let held):
                return String(
                    format: "PressTalk only recorded %.1f of %.1f seconds. "
                        + "The microphone may have been switched or busy. "
                        + "Nothing was inserted.", captured, held)
            }
        }
    }

    /// Below this the signal carries no speech at any usable gain. A quiet room
    /// on a condenser microphone still measures around 0.002; hardware mute and
    /// a dead stream both measure exactly zero.
    public static let silenceRMSFloor = 0.00005

    /// How much of the hold must survive as audio. Some loss is normal: the
    /// engine takes time to start, and the trigger is released before the last
    /// buffer arrives. Losing more than half of a deliberate hold is not.
    public static let minimumCapturedFraction = 0.5

    /// Below this a hold is too short to reason about proportionally -- a
    /// 0.3 s tap that yields 0.1 s of audio is a stray keypress, not a fault,
    /// and telling someone their microphone is broken would be wrong.
    public static let minimumHeldSecondsForTruncationCheck = 3.0

    public static func evaluate(
        capturedSeconds: Double,
        heldSeconds: Double,
        rms: Double,
        peak: Double
    ) -> Verdict {
        // Silence first. A recording that is both silent and truncated is a
        // dead input, and naming the microphone is more useful than naming the
        // shortfall.
        if rms <= silenceRMSFloor && peak <= silenceRMSFloor {
            return .silent
        }
        guard heldSeconds >= minimumHeldSecondsForTruncationCheck else {
            return .usable
        }
        if capturedSeconds < heldSeconds * minimumCapturedFraction {
            return .truncated(capturedSeconds: capturedSeconds, heldSeconds: heldSeconds)
        }
        return .usable
    }
}
