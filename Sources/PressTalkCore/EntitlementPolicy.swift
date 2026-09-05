import Foundation

/// Decides what a given installation is entitled to.
///
/// The awkward part is history. PressTalk's shipped settings pane has been
/// telling people "core local dictation remains free" for months. Turning those
/// installations into expired trials the moment a paid build lands would be a
/// promise withdrawn from the exact users who tried it first, so they are
/// grandfathered by evidence of prior use, and a trial only ever applies to
/// someone who arrives after the paid release.
public struct EntitlementPolicy {
    public enum State: Equatable {
        /// Used PressTalk before it was paid. Keeps core dictation, no licence
        /// required, no expiry.
        case grandfathered
        case licensed(entitlement: String)
        case trial(daysRemaining: Int)
        case trialExpired

        /// Advisory only. Nothing in the app calls this yet, and that is
        /// deliberate rather than an oversight: enforcing expiry before there is
        /// a way to buy a licence would lock people out of a product they cannot
        /// pay for. Classifying correctly and enforcing are separate steps, and
        /// wiring this up is a decision for whoever turns on the checkout.
        /// Recorded in docs/LAUNCH_GATES.md as an open gate.
        public var allowsDictation: Bool {
            switch self {
            case .grandfathered, .licensed, .trial: return true
            case .trialExpired: return false
            }
        }
    }

    /// Whether this installation predates paid licensing.
    ///
    /// This is a single decision recorded once, not a heuristic re-evaluated on
    /// every launch, and the difference is the whole point. The first version of
    /// this read live flags -- "has seen the setup guide", "has delivered a
    /// dictation" -- and every one of those is also set by a brand new install
    /// within seconds of its first launch. It grandfathered everybody. The trial
    /// could never begin, and no test caught it, because the tests handed the
    /// policy its evidence directly while the real app handed it the wrong
    /// evidence.
    ///
    /// See `InstallGeneration`, which decides once, before anything writes.
    public struct PriorUseEvidence {
        public let predatesPaidLicensing: Bool

        public init(predatesPaidLicensing: Bool) {
            self.predatesPaidLicensing = predatesPaidLicensing
        }

        public var indicatesPriorUse: Bool { predatesPaidLicensing }
    }

    public let trialDays: Int

    public init(trialDays: Int = 14) {
        self.trialDays = max(0, trialDays)
    }

    /// A verified licence wins over everything. Then prior use. Then the trial,
    /// which is measured from the first successful dictation rather than from
    /// install: a trial that starts ticking while someone is still downloading a
    /// model is a trial they did not get.
    public func state(
        verifiedEntitlement: String?,
        priorUse: PriorUseEvidence,
        trialStartedAt: Date?,
        now: Date
    ) -> State {
        if let verifiedEntitlement {
            return .licensed(entitlement: verifiedEntitlement)
        }
        if priorUse.indicatesPriorUse {
            return .grandfathered
        }
        guard let trialStartedAt else {
            return .trial(daysRemaining: trialDays)
        }
        let elapsedDays = now.timeIntervalSince(trialStartedAt) / 86_400
        let remaining = Int((Double(trialDays) - elapsedDays).rounded(.up))
        return remaining > 0 ? .trial(daysRemaining: remaining) : .trialExpired
    }
}

/// The single place prices are written down.
///
/// They had been in three places saying three things: a settings string offering
/// "Pro $8/mo or $59/yr, Founding $49 lifetime", a roadmap document specifying
/// $20 then $39 one-time, and a reviewer's note suggesting euros. Whichever is
/// right, a product cannot ship all three.
public enum PressTalkOffer {
    public static let founderPriceUSD = 20
    public static let personalPriceUSD = 39

    /// What the money buys. Deliberately narrow: "updates through 1.x" is
    /// checkable in the licence, "lifetime updates" is not a promise anyone can
    /// keep.
    public static let founderSummary =
        "PressTalk Founder — $\(founderPriceUSD) once. Updates through 1.x. No subscription."
    public static let personalSummary =
        "PressTalk Personal — $\(personalPriceUSD) once. Updates through 1.x. No subscription."

    public static func stateSummary(_ state: EntitlementPolicy.State) -> String {
        switch state {
        case .grandfathered:
            return "Free — you used PressTalk before it was paid, so core dictation stays free on this Mac."
        case .licensed(let entitlement):
            return "Licensed (\(entitlement)). Updates through 1.x."
        case .trial(let daysRemaining):
            let dayWord = daysRemaining == 1 ? "day" : "days"
            return "Trial — \(daysRemaining) \(dayWord) left. \(founderSummary)"
        case .trialExpired:
            return "Trial finished. \(founderSummary)"
        }
    }
}


/// Answers "did this installation exist before PressTalk was paid?" exactly once.
///
/// The answer has to be taken at the very start of the first launch of a
/// licensing-aware build, before any first-run default is written, and then
/// stored. Asked a second later it is already wrong: a new install has by then
/// set the same flags an old one carries.
public enum InstallGeneration {
    /// Only ever call this before first-run state is written. Flags observed at
    /// that instant can only have come from an earlier version of the app.
    public static func predatesPaidLicensing(
        hasSeenSetupGuide: Bool,
        hasDeliveredDictation: Bool
    ) -> Bool {
        hasSeenSetupGuide || hasDeliveredDictation
    }
}
