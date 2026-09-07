import Foundation

/// Turns a crash during microphone start into a one-time, explained downgrade.
///
/// WHY THIS EXISTS
/// `AVAudioNode.installTap` raises an Objective-C exception when the format it
/// is handed disagrees with the node it is handed to. Swift cannot catch an
/// NSException, so that exception is not an error the app can handle -- it is
/// SIGABRT, mid-sentence. `AudioInputPreflightPolicy` exists to keep a bad
/// format from ever reaching that call, and it does its job, but it is a
/// PREDICTION: it reads the device now and the engine opens it a moment later.
/// Whatever changes in between is invisible to it.
///
/// So this assumes the prediction will eventually be wrong. The device about to
/// be opened is written down before the attempt and erased as soon as audio is
/// flowing. A record still sitting there at the next launch means the process
/// did not survive the last attempt, and the microphone it was opening is the
/// prime suspect. PressTalk then falls back to the system default and says so,
/// instead of reopening the same device and dying again on every launch.
///
/// The downgrade is deliberately one-shot and reversible. A record can also be
/// left behind by an ordinary kill -- a restart or a `launchctl bootout` that
/// lands inside the sub-second window while the engine is starting -- so this
/// must never silently latch a microphone off. It reverts once, explains itself
/// in the user's words, and the choice is one click away in Settings.
public struct AudioInputCrashBreaker {
    /// The microphone an attempt was made on, as recorded before the attempt.
    public struct Attempt: Equatable {
        public let deviceUID: String
        /// What to call the device when explaining this to a person. Recorded
        /// alongside the UID because by the time the message is shown the
        /// device may be unplugged and no longer nameable.
        public let deviceName: String

        public init(deviceUID: String, deviceName: String) {
            self.deviceUID = deviceUID
            self.deviceName = deviceName
        }
    }

    public struct Outcome: Equatable {
        public let revertToSystemDefault: Bool
        /// Plain-language explanation, or nil when there is nothing to say.
        public let userMessage: String?

        public static let noAction = Outcome(revertToSystemDefault: false, userMessage: nil)
    }

    public init() {}

    /// `unfinishedAttempt` is whatever survived from the last run: nil when the
    /// last microphone start completed, or the app was never asked for a
    /// specific device.
    public func evaluate(unfinishedAttempt: Attempt?) -> Outcome {
        guard let attempt = unfinishedAttempt else { return .noAction }
        // A record with no usable identity cannot be acted on and cannot be
        // explained. Clearing it without reverting is the honest response:
        // reverting would blame a microphone this cannot name.
        let name = attempt.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attempt.deviceUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .noAction
        }
        let spoken = name.isEmpty ? "the microphone you chose" : name
        return Outcome(
            revertToSystemDefault: true,
            userMessage: "PressTalk stopped unexpectedly while starting \(spoken), "
                       + "so it is using your system default microphone for now. "
                       + "You can choose \(spoken) again in Settings."
        )
    }
}
