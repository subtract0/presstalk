import Foundation

/// Decides what a new user is asked for, in what order, and when setup is
/// genuinely finished.
///
/// Kept free of AppKit so the ordering rules can be tested. The rules matter
/// more than they look: macOS grants these permissions independently, a person
/// can revoke one at any time, and asking for all three at once produces three
/// stacked system dialogs that most people dismiss.
public struct FirstRunSetupPolicy {
    public enum Step: String, CaseIterable, Codable {
        /// Without this there is no audio at all, so it goes first.
        case microphone
        /// The trigger key. Only some triggers need it.
        case inputMonitoring
        /// Pasting into another app. Absent, PressTalk can still copy.
        case accessibility
        /// The speech model has to exist before the first dictation.
        case speechModel
        /// Text has to actually arrive somewhere the user can see.
        case firstDictation
    }

    public enum StepState: String, Codable {
        case pending
        case inProgress
        case satisfied
        /// Explicitly refused or unavailable, and the user can continue anyway.
        case skipped
        case failed
    }

    public struct Conditions {
        public let microphoneCaptureVerified: Bool
        public let inputMonitoringGranted: Bool
        public let accessibilityGranted: Bool
        public let speechModelReady: Bool
        public let firstDictationDelivered: Bool
        public let triggerRequiresInputMonitoring: Bool

        public init(
            microphoneCaptureVerified: Bool,
            inputMonitoringGranted: Bool,
            accessibilityGranted: Bool,
            speechModelReady: Bool,
            firstDictationDelivered: Bool,
            triggerRequiresInputMonitoring: Bool
        ) {
            self.microphoneCaptureVerified = microphoneCaptureVerified
            self.inputMonitoringGranted = inputMonitoringGranted
            self.accessibilityGranted = accessibilityGranted
            self.speechModelReady = speechModelReady
            self.firstDictationDelivered = firstDictationDelivered
            self.triggerRequiresInputMonitoring = triggerRequiresInputMonitoring
        }
    }

    public init() {}

    /// The steps this configuration actually needs. A trigger that does not use
    /// an event tap must not make someone grant Input Monitoring for nothing.
    public func steps(for conditions: Conditions) -> [Step] {
        var steps: [Step] = [.microphone]
        if conditions.triggerRequiresInputMonitoring {
            steps.append(.inputMonitoring)
        }
        steps.append(contentsOf: [.accessibility, .speechModel, .firstDictation])
        return steps
    }

    public func state(of step: Step, given conditions: Conditions) -> StepState {
        switch step {
        case .microphone:
            // Deliberately not the authorization status. That reads .authorized
            // through stale grants and dead devices; only captured frames prove
            // a microphone works. See AudioCaptureProbeReport.
            return conditions.microphoneCaptureVerified ? .satisfied : .pending
        case .inputMonitoring:
            return conditions.inputMonitoringGranted ? .satisfied : .pending
        case .accessibility:
            return conditions.accessibilityGranted ? .satisfied : .pending
        case .speechModel:
            return conditions.speechModelReady ? .satisfied : .pending
        case .firstDictation:
            return conditions.firstDictationDelivered ? .satisfied : .pending
        }
    }

    /// The one step to put in front of the user. Returning a single step is the
    /// point: three simultaneous system dialogs are three chances to say no.
    public func currentStep(for conditions: Conditions) -> Step? {
        steps(for: conditions).first { state(of: $0, given: conditions) != .satisfied }
    }

    /// Setup is complete when text has actually been delivered, not when the
    /// permissions look right. Accessibility is excluded on purpose: PressTalk
    /// copies to the clipboard when it cannot paste, which is a worse experience
    /// but a working one, and refusing to finish setup over it would strand
    /// anyone whose Mac is managed.
    public func isComplete(_ conditions: Conditions) -> Bool {
        guard conditions.microphoneCaptureVerified else { return false }
        if conditions.triggerRequiresInputMonitoring, !conditions.inputMonitoringGranted { return false }
        guard conditions.speechModelReady else { return false }
        return conditions.firstDictationDelivered
    }

    /// How far along to show. Counts satisfied steps against the ones this
    /// configuration needs, so a trigger that skips Input Monitoring does not
    /// report 80% forever.
    public func progress(_ conditions: Conditions) -> Double {
        let required = steps(for: conditions)
        guard !required.isEmpty else { return 1 }
        let done = required.filter { state(of: $0, given: conditions) == .satisfied }.count
        return Double(done) / Double(required.count)
    }
}

public extension FirstRunSetupPolicy.Step {
    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .inputMonitoring: return "Trigger key"
        case .accessibility: return "Pasting into apps"
        case .speechModel: return "Speech model"
        case .firstDictation: return "Your first dictation"
        }
    }

    /// Says what the permission is for in terms of what the person gets, not
    /// what the API is called.
    var explanation: String {
        switch self {
        case .microphone:
            return "PressTalk needs to hear you. Audio stays on this Mac and is not uploaded."
        case .inputMonitoring:
            return "So PressTalk notices when you hold the trigger key. It watches for that key, "
                + "and does not record what you type."
        case .accessibility:
            return "So the text lands in the app you are working in. Without it PressTalk copies "
                + "the text to the clipboard instead, and you paste it yourself."
        case .speechModel:
            return "A one-time download of the speech recognition model. It runs on this Mac afterwards."
        case .firstDictation:
            return "Hold the trigger key, say a sentence, and let go."
        }
    }

    /// Whether setup can proceed without it.
    var isOptional: Bool { self == .accessibility }
}
