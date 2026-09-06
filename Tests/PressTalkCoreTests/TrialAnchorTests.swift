import XCTest
@testable import PressTalkCore

/// The trial's whole job is to end. These tests are mostly about the ways it
/// could fail to end, or end for the wrong person.
final class TrialAnchorTests: XCTestCase {

    private let day = 86_400.0
    private var t0: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    // MARK: earliest wins

    func testEarliestDateWinsRegardlessOfOrder() {
        let early = t0
        let late = t0.addingTimeInterval(5 * day)
        XCTAssertEqual(TrialAnchor.resolve([.found(early), .found(late)]).startedAt, early)
        XCTAssertEqual(TrialAnchor.resolve([.found(late), .found(early)]).startedAt, early)
    }

    /// The reinstall someone actually performs: delete the app, delete the
    /// preference file, install again. UserDefaults comes back empty; the
    /// keychain still holds the original date. A fresh trial must not begin.
    func testDeletingOneStoreDoesNotRestartTheTrial() {
        let original = t0
        let resolution = TrialAnchor.resolve([.absent, .found(original)])
        XCTAssertEqual(resolution.startedAt, original)
        XCTAssertTrue(resolution.isTrustworthy)
        XCTAssertTrue(TrialAnchor.mayEnforceExpiry(resolution))
    }

    /// And the emptied store is refilled, so the same trick does not work twice.
    func testAnEmptiedStoreIsHealedFromTheSurvivor() {
        XCTAssertEqual(TrialAnchor.resolve([.absent, .found(t0)]).storesToHeal, [0])
        XCTAssertEqual(TrialAnchor.resolve([.found(t0), .absent]).storesToHeal, [1])
        XCTAssertEqual(
            TrialAnchor.resolve([.absent, .found(t0), .absent]).storesToHeal, [0, 2])
    }

    // MARK: genuine first run

    func testNoStoreHoldingADateIsAFirstRunNotAnExpiry() {
        let resolution = TrialAnchor.resolve([.absent, .absent])
        XCTAssertNil(resolution.startedAt)
        XCTAssertTrue(resolution.isTrustworthy)
        // Nothing to enforce: the trial has not started.
        XCTAssertFalse(TrialAnchor.mayEnforceExpiry(resolution))
    }

    func testAFirstRunHealsNothing() {
        // Writing a resolved date into every store when there is no date would
        // mean writing nil, or worse, "now" into a store that is about to be
        // written properly by starting the trial.
        XCTAssertEqual(TrialAnchor.resolve([.absent, .absent]).storesToHeal, [])
    }

    // MARK: unreadable stores must not lock anyone out

    /// A locked keychain is not evidence that a trial never started, and it is
    /// not evidence that one expired. The app cannot prove anything, so it must
    /// not act.
    func testAnUnreadableStoreMakesTheReadingUntrustworthy() {
        XCTAssertFalse(TrialAnchor.resolve([.unavailable, .absent]).isTrustworthy)
        XCTAssertFalse(TrialAnchor.resolve([.unavailable, .found(t0)]).isTrustworthy)
        XCTAssertFalse(TrialAnchor.resolve([.unavailable, .unavailable]).isTrustworthy)
    }

    func testExpiryIsNeverEnforcedOnAnUntrustworthyReading() {
        // Even with a start date old enough to have expired many times over,
        // an unreadable store means no enforcement.
        let ancient = t0.addingTimeInterval(-3650 * day)
        let resolution = TrialAnchor.resolve([.unavailable, .found(ancient)])
        XCTAssertNotNil(resolution.startedAt)
        XCTAssertFalse(TrialAnchor.mayEnforceExpiry(resolution))
    }

    /// The dangerous confusion, stated as its own test: if `unavailable` were
    /// ever folded into `absent`, this reading would look like a first run and
    /// hand out a fresh trial.
    func testUnavailableIsNotTreatedAsAbsent() {
        let unreadable = TrialAnchor.resolve([.unavailable])
        let empty = TrialAnchor.resolve([.absent])
        XCTAssertNil(unreadable.startedAt)
        XCTAssertNil(empty.startedAt)
        XCTAssertNotEqual(unreadable.isTrustworthy, empty.isTrustworthy)
        XCTAssertEqual(unreadable.storesToHeal, [])
    }

    /// An unreadable store is never written to. It may already hold the real
    /// date, and overwriting it with a later one would extend the trial.
    func testUnreadableStoresAreNeverHealed() {
        XCTAssertEqual(
            TrialAnchor.resolve([.unavailable, .found(t0)]).storesToHeal, [])
        XCTAssertEqual(
            TrialAnchor.resolve([.unavailable, .absent, .found(t0)]).storesToHeal, [1])
    }

    // MARK: interaction with the policy

    func testThreeDayTrialExpiresOnTheFourthDay() {
        let policy = EntitlementPolicy(trialDays: 3)
        let fresh = EntitlementPolicy.PriorUseEvidence(predatesPaidLicensing: false)
        func state(after days: Double) -> EntitlementPolicy.State {
            policy.state(verifiedEntitlement: nil, priorUse: fresh,
                         trialStartedAt: t0, now: t0.addingTimeInterval(days * day))
        }
        XCTAssertEqual(state(after: 0), .trial(daysRemaining: 3))
        XCTAssertEqual(state(after: 2.5), .trial(daysRemaining: 1))
        XCTAssertEqual(state(after: 3.01), .trialExpired)
        XCTAssertEqual(state(after: 400), .trialExpired)
    }

    /// The people who used PressTalk while it was free keep it, no matter what
    /// any store says about a trial.
    func testPriorUseBeatsAnExpiredAnchor() {
        let policy = EntitlementPolicy(trialDays: 3)
        let old = EntitlementPolicy.PriorUseEvidence(predatesPaidLicensing: true)
        XCTAssertEqual(
            policy.state(verifiedEntitlement: nil, priorUse: old,
                         trialStartedAt: t0.addingTimeInterval(-99 * day),
                         now: t0),
            .grandfathered)
    }

    func testAVerifiedLicenceBeatsAnExpiredAnchor() {
        let policy = EntitlementPolicy(trialDays: 3)
        let fresh = EntitlementPolicy.PriorUseEvidence(predatesPaidLicensing: false)
        XCTAssertEqual(
            policy.state(verifiedEntitlement: "founder", priorUse: fresh,
                         trialStartedAt: t0.addingTimeInterval(-99 * day),
                         now: t0),
            .licensed(entitlement: "founder"))
    }
}
