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

        public var allowsDictation: Bool {
            switch self {
            case .grandfathered, .licensed, .trial: return true
            case .trialExpired: return false
            }
        }
    }

    /// Evidence that this install predates paid licensing. Any one of these is
    /// enough: the failure this guards against -- silently revoking a promise --
    /// is far worse than occasionally grandfathering someone who reinstalled.
    public struct PriorUseEvidence {
        public let hasSeenSetupGuide: Bool
        public let hasDeliveredDictation: Bool
        public let hasStoredPlanTier: Bool

        public init(hasSeenSetupGuide: Bool, hasDeliveredDictation: Bool, hasStoredPlanTier: Bool) {
            self.hasSeenSetupGuide = hasSeenSetupGuide
            self.hasDeliveredDictation = hasDeliveredDictation
            self.hasStoredPlanTier = hasStoredPlanTier
        }

        public var indicatesPriorUse: Bool {
            hasSeenSetupGuide || hasDeliveredDictation || hasStoredPlanTier
        }
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
