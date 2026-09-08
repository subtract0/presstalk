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
        trialStartedAt: @autoclosure () -> Date?,
        now: Date
    ) -> State {
        if let verifiedEntitlement {
            return .licensed(entitlement: verifiedEntitlement)
        }
        if priorUse.indicatesPriorUse {
            return .grandfathered
        }
        // The app's anchor includes Keychain access. A paid or early-user
        // licence must return above without reading an irrelevant trial record.
        guard let trialStartedAt = trialStartedAt() else {
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
    /// How someone pays. More than one, because the owner asked for both.
    ///
    /// These are not interchangeable and the difference is not cosmetic:
    /// **Stripe Managed Payments makes Stripe the merchant of record**, so
    /// Stripe collects and remits VAT and is the contracting seller. A direct
    /// PayPal checkout does NOT do that -- PayPal is a processor, the seller
    /// remains the supplier and accounts for the VAT itself. Adding the second
    /// button therefore changes who accounts for the tax, per transaction,
    /// depending on which one the buyer pressed. Who the CONTRACTING seller is
    /// is a separate question the tax fiction does not answer.
    /// See docs/MONETIZATION.md before touching either value.
    public enum CheckoutRail: String, CaseIterable, Equatable {
        case stripe
        case paypal

        /// Whether someone else is the deemed supplier **for indirect tax**.
        ///
        /// Narrower than it first read here. Stripe's own Managed Payments
        /// terms say it is "not the seller of record" and is deemed supplier
        /// "for Indirect Tax purposes only" -- so this answers who accounts for
        /// VAT, and does NOT establish who the contracting seller is or who
        /// carries the consumer-law duties. Those depend on the customer terms
        /// actually in force and are checked in docs/launch/DAY1_CHECKS.md, not
        /// decided by this boolean.
        public var isDeemedSupplierForTax: Bool {
            switch self {
            case .stripe: return true
            case .paypal: return false
            }
        }

        public var displayName: String {
            switch self {
            case .stripe: return "Card"
            case .paypal: return "PayPal"
            }
        }
    }

    /// The purchase service checks sales readiness before opening the existing
    /// Stripe Managed Payments checkout. Receipts and recovery remain available
    /// when new sales are paused.
    public static let checkoutURLString = "https://presstalk.app/buy.html"

    /// Direct PayPal checkout against the business account
    /// `connect@alexmonas.com`. **Empty until the owner creates the button.**
    ///
    /// Nobody but the account holder can produce this value -- it requires
    /// signing in to PayPal, which is his to do and not mine. Empty behaves
    /// exactly as the Stripe one did before it was filled in: the button stays
    /// hidden and nothing claims to accept PayPal.
    public static let paypalCheckoutURLString = ""

    /// Where the offer is described. Empty until a domain exists.
    public static let pricingPageURLString = "https://presstalk.app/download.html#buy"

    public static func checkoutURLString(for rail: CheckoutRail) -> String {
        switch rail {
        case .stripe: return checkoutURLString
        case .paypal: return paypalCheckoutURLString
        }
    }

    /// Every rail that can actually take money right now, in the order they
    /// should be offered. An empty rail is absent rather than broken: a button
    /// that leads nowhere is worse than no button.
    public static var liveCheckoutRails: [CheckoutRail] {
        CheckoutRail.allCases.filter { checkoutURL(for: $0) != nil }
    }

    public static func checkoutURL(for rail: CheckoutRail) -> URL? {
        let raw = checkoutURLString(for: rail).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : URL(string: raw)
    }

    /// The Stripe rail, kept under its original name because the app opens a
    /// single URL in a few places and Stripe is the one that is live.
    public static var checkoutURL: URL? { checkoutURL(for: .stripe) }

    public static var pricingPageURL: URL? {
        pricingPageURLString.isEmpty ? nil : URL(string: pricingPageURLString)
    }

    /// Whether anyone can actually buy this right now, by ANY route.
    ///
    /// This gates trial enforcement, so it has to mean "a person could pay if
    /// they wanted to". Asking only about Stripe would refuse dictation to
    /// someone whose only working checkout was PayPal.
    public static var checkoutIsLive: Bool { !liveCheckoutRails.isEmpty }

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
        "PressTalk Founder — €20 / US$20 / CA$28 once. Every future Mac update included, major versions too. No subscription."
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
