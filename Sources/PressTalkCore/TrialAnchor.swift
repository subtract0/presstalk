import Foundation

/// Decides when a trial started, across several places it might be recorded.
///
/// A trial kept only in UserDefaults resets when someone deletes the app and
/// its preference file, which makes "3 days" mean "3 days, repeatedly, forever".
/// The fix is to record the same date in more than one store and always believe
/// the *earliest* one, so removing any single store does not buy more time.
///
/// The hard part is not the earliest-wins rule. It is telling "this store says
/// there is no date" apart from "this store could not be read". Treating an
/// unreadable keychain as an absent date would restart the trial for a paying
/// customer whose keychain was simply locked, and treating an absent date as
/// unreadable would never let a genuine first run begin. They are different
/// answers and the caller has to act differently on each, so `Reading` keeps
/// them separate all the way through.
public enum TrialAnchor {

    /// What one store had to say.
    public enum Reading: Equatable {
        /// The store holds this date.
        case found(Date)
        /// The store was read successfully and holds nothing.
        case absent
        /// The store could not be read. This says nothing about whether a date
        /// exists in it, and must never be treated as `absent`.
        case unavailable
    }

    public struct Resolution: Equatable {
        /// The earliest date any store reported, or nil if none did.
        public let startedAt: Date?

        /// Indices of stores that reported `absent` while another store held a
        /// date. Writing the resolved date back to these restores redundancy,
        /// so deleting one store again does not help. Never contains a store
        /// that reported `unavailable` -- writing into a store that could not
        /// be read risks overwriting a date it already holds.
        public let storesToHeal: [Int]

        /// False when at least one store could not be read. The recorded state
        /// may be older than what is visible here, so a caller must not enforce
        /// an expiry on this reading. Enforcement fails open by design: a bug in
        /// this code must never lock out someone who paid.
        public let isTrustworthy: Bool

        public init(startedAt: Date?, storesToHeal: [Int], isTrustworthy: Bool) {
            self.startedAt = startedAt
            self.storesToHeal = storesToHeal
            self.isTrustworthy = isTrustworthy
        }
    }

    /// Earliest date wins. Absent stores get healed; unavailable ones never do.
    public static func resolve(_ readings: [Reading]) -> Resolution {
        var earliest: Date?
        var absentIndices: [Int] = []
        var sawUnavailable = false

        for (index, reading) in readings.enumerated() {
            switch reading {
            case .found(let date):
                if earliest == nil || date < earliest! { earliest = date }
            case .absent:
                absentIndices.append(index)
            case .unavailable:
                sawUnavailable = true
            }
        }

        return Resolution(
            startedAt: earliest,
            // Nothing to heal when no store holds a date: that is a genuine
            // first run, and the caller starts the trial rather than healing.
            storesToHeal: earliest == nil ? [] : absentIndices,
            isTrustworthy: !sawUnavailable)
    }

    /// Whether an expiry may be enforced on this reading.
    ///
    /// Separated from `resolve` so the decision to lock someone out is a single
    /// named thing that a test can hold. Enforcement requires a trustworthy
    /// reading *and* a known start date; anything else means the app cannot
    /// prove the trial is over, and an app that cannot prove it must not act.
    public static func mayEnforceExpiry(_ resolution: Resolution) -> Bool {
        resolution.isTrustworthy && resolution.startedAt != nil
    }
}
