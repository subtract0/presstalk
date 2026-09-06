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

        /// Whether this state permits dictation, considered alone.
        ///
        /// Not the enforcement decision. The app asks
        /// `PressTalkLicenseStore.shouldBlockDictation`, which additionally
        /// requires that the trial anchor was readable and that a checkout
        /// exists to buy from. Refusing to dictate while offering no way to pay
        /// is a broken app rather than a paywall, so while
        /// `PressTalkOffer.checkoutURLString` is empty this refuses nobody.
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

    /// Three days, not fourteen. At $20 this is an impulse purchase, and a
    /// fortnight does not help someone decide -- it lets them forget. Three days
    /// covers a couple of real working sessions, which is what the decision
    /// actually needs.
    public init(trialDays: Int = 3) {
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
    /// The Lemon Squeezy checkout. **Set this string when the store goes live.**
    ///
    /// One line, one place. While it is empty the buy button stays hidden, which
    /// is honest: there is nowhere to pay. `PRESSTALK_CHECKOUT_URL` overrides it
    /// for staging.
    public static let checkoutURLString = ""

    /// Where the offer is described. Empty until a domain exists.
    public static let pricingPageURLString = ""

    public static var checkoutURL: URL? {
        checkoutURLString.isEmpty ? nil : URL(string: checkoutURLString)
    }

    public static var pricingPageURL: URL? {
        pricingPageURLString.isEmpty ? nil : URL(string: pricingPageURLString)
    }

    /// Whether anyone can actually buy this right now.
    public static var checkoutIsLive: Bool { checkoutURL != nil }

    public static let founderPriceUSD = 20
    public static let personalPriceUSD = 39

    /// What the money buys, and what it does not.
    ///
    /// Two different promises get confused here, and only one of them is
    /// dangerous. "Every update we release is free to you" costs nothing extra
    /// per customer and is what someone means by not wanting to be rented to.
    /// "We will keep releasing updates forever" is unbounded labour by one
    /// person against a platform that changes annually, and nobody can honour
    /// it. So the offer includes every future release and promises no schedule,
    /// and the disclaimer is part of the offer rather than buried in a FAQ.
    public static let founderSummary =
        "PressTalk Founder — $\(founderPriceUSD) once. Every future Mac update included, major versions too. No subscription."
    public static let personalSummary =
        "PressTalk Personal — $\(personalPriceUSD) once. Every future Mac update included, major versions too. No subscription."
    public static let updateDisclaimer =
        "Future releases, indefinite support, and compatibility with future macOS versions are not guaranteed."

    public static func stateSummary(_ state: EntitlementPolicy.State) -> String {
        switch state {
        case .grandfathered:
            return "Free — you used PressTalk before it was paid, so core dictation stays free on this Mac."
        case .licensed(let entitlement):
            return "Licensed (\(entitlement)). Every future Mac update included."
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
