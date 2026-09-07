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
        /// Silent, and macOS reports that all audio input to *this process*
        /// is muted. That is a specific, checkable fact --
        /// kAudioHardwarePropertyProcessInputMute -- and it is the only mute
        /// claim this app can honestly make.
        ///
        /// It replaced a claim that a named device's hardware switch was on.
        /// That was asserted from kAudioDevicePropertyMute, which reports the
        /// state of an AudioMuteControl on an element and says nothing about a
        /// physical switch or who set it. It told the owner his microphone was
        /// muted while another app was recording from it happily.
        case inputMutedForThisApp
        /// Far less audio arrived than the key was held for.
        case truncated(capturedSeconds: Double, heldSeconds: Double)
        /// The recording is usable, but the microphone took long enough to
        /// start that the opening words were probably missed. Bluetooth is the
        /// usual reason: measured on this machine, AirPods take about 1.2 s to
        /// start where a USB microphone takes 0.33 s, and 1.2 s is five or six
        /// syllables. Reported so the person knows why their sentence began
        /// mid-word, rather than concluding the recogniser is bad.
        case startedLate(lostSeconds: Double)

        /// A late start still produced usable audio. The text is delivered and
        /// the person is told why it begins where it does; refusing it would
        /// throw away a sentence they did say.
        public var isUsable: Bool {
            if case .startedLate = self { return true }
            return self == .usable
        }

        /// What to tell the person, in their terms. They pressed a key and
        /// spoke; the failure is not theirs and the message should not read
        /// like it is.
        public var userFacingMessage: String? {
            switch self {
            case .usable:
                return nil
            case .startedLate(let lost):
                // States what the app knows -- when recording began -- and not
                // that words were lost. It cannot tell the difference between
                // someone who spoke immediately and someone who waited for the
                // indicator, and the second person should not be told they were
                // cut off. The distinction survived review only because it was
                // read aloud against a case where nothing was missed.
                return String(
                    format: "Your microphone took %.1f s to start, so anything "
                        + "said in that first moment is not in this text. "
                        + "Bluetooth headsets are slower to wake — wait for the "
                        + "indicator to fill before speaking.", lost)
            case .inputMutedForThisApp:
                return "macOS is muting microphone input for PressTalk. Check "
                    + "the microphone indicator in the menu bar, and any app or "
                    + "key that mutes your input."
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
    /// Was 3.0, which exempted the real failure it was written for: a 2.75 s
    /// hold that captured 0.30 s after 2.4 s of engine startup. That is 89% of
    /// the speech gone, reported as ordinary silence. A stray tap is short in
    /// absolute terms, so 1.0 s still excludes it while catching a hold someone
    /// meant.
    public static let minimumHeldSecondsForTruncationCheck = 1.0

    /// `inputMutedForThisProcess` comes from
    /// kAudioHardwarePropertyProcessInputMute, which states that every input
    /// this process receives will be silent. Unknown or unsupported must arrive
    /// as false: an absent property is not a mute, and guessing produced a
    /// confidently wrong diagnosis once already.
    /// How slow a start counts as having cost the user words. A USB
    /// microphone starts in about a third of a second and nobody notices; at
    /// three quarters of a second there is a syllable or two gone.
    public static let lateStartSeconds = 0.75

    public static func evaluate(
        capturedSeconds: Double,
        heldSeconds: Double,
        rms: Double,
        peak: Double,
        inputMutedForThisProcess: Bool = false,
        engineStartSeconds: Double = 0
    ) -> Verdict {
        // Silence first. A recording that is both silent and truncated is a
        // dead input, and naming the microphone is more useful than naming the
        // shortfall.
        if rms <= silenceRMSFloor && peak <= silenceRMSFloor {
            // Only claimed when macOS says so about this process. Every other
            // cause of silence -- an unplugged interface, a switch on the
            // hardware, another app holding the device -- looks identical in
            // the samples, and naming the wrong one sends someone hunting in
            // the wrong place.
            if inputMutedForThisProcess { return .inputMutedForThisApp }
            return .silent
        }
        guard heldSeconds >= minimumHeldSecondsForTruncationCheck else {
            return .usable
        }
        if capturedSeconds < heldSeconds * minimumCapturedFraction {
            return .truncated(capturedSeconds: capturedSeconds, heldSeconds: heldSeconds)
        }
        // Reported after truncation, not instead of it: losing most of the hold
        // is the bigger problem and deserves the message.
        if engineStartSeconds >= lateStartSeconds {
            return .startedLate(lostSeconds: engineStartSeconds)
        }
        return .usable
    }
}
