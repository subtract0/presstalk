import XCTest
@testable import PressTalkCore

final class EntitlementPolicyTests: XCTestCase {
    private let policy = EntitlementPolicy(trialDays: 14)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func evidence(predates: Bool = false) -> EntitlementPolicy.PriorUseEvidence {
        .init(predatesPaidLicensing: predates)
    }

    // The shipped settings pane has been promising free core dictation for
    // months. Anyone already using it keeps that.
    func testExistingUsersAreGrandfathered() {
        XCTAssertEqual(
            policy.state(
                verifiedEntitlement: nil, priorUse: evidence(predates: true),
                trialStartedAt: nil, now: now),
            .grandfathered)
    }

    // The bug this replaced: the decision used to be re-derived on every launch
    // from flags a brand new install sets within seconds of starting, so every
    // user was grandfathered and the trial could never begin. It is now taken
    // once, before anything writes.
    func testANewInstallIsNotGrandfathered() {
        XCTAssertFalse(
            InstallGeneration.predatesPaidLicensing(
                hasSeenSetupGuide: false, hasDeliveredDictation: false))
        XCTAssertEqual(
            policy.state(
                verifiedEntitlement: nil, priorUse: evidence(predates: false),
                trialStartedAt: nil, now: now),
            .trial(daysRemaining: 14))
    }

    // Anyone carrying state from a pre-licensing build keeps free core dictation.
    func testAnInstallCarryingOlderStatePredatesLicensing() {
        XCTAssertTrue(
            InstallGeneration.predatesPaidLicensing(
                hasSeenSetupGuide: true, hasDeliveredDictation: false))
        XCTAssertTrue(
            InstallGeneration.predatesPaidLicensing(
                hasSeenSetupGuide: false, hasDeliveredDictation: true))
    }

    // The exact failure this design exists to prevent.
    func testAnExistingUserIsNeverTurnedIntoAnExpiredTrial() {
        let longAgo = now.addingTimeInterval(-365 * 86_400)
        let state = policy.state(
            verifiedEntitlement: nil, priorUse: evidence(predates: true),
            trialStartedAt: longAgo, now: now)
        XCTAssertEqual(state, .grandfathered)
        XCTAssertTrue(state.allowsDictation)
    }

    func testANewInstallStartsWithAFullTrial() {
        XCTAssertEqual(
            policy.state(verifiedEntitlement: nil, priorUse: evidence(predates: false), trialStartedAt: nil, now: now),
            .trial(daysRemaining: 14))
    }

    // Measured from first successful dictation, not install: a trial ticking
    // down during a model download is a trial the buyer did not get.
    func testTheTrialCountsDownFromFirstDictation() {
        let started = now.addingTimeInterval(-10 * 86_400)
        XCTAssertEqual(
            policy.state(verifiedEntitlement: nil, priorUse: evidence(predates: false), trialStartedAt: started, now: now),
            .trial(daysRemaining: 4))
    }

    func testTheTrialExpires() {
        let started = now.addingTimeInterval(-15 * 86_400)
        let state = policy.state(
            verifiedEntitlement: nil, priorUse: evidence(predates: false), trialStartedAt: started, now: now)
        XCTAssertEqual(state, .trialExpired)
        XCTAssertFalse(state.allowsDictation)
    }

    func testTheLastDayIsStillATrialDay() {
        let started = now.addingTimeInterval(-13.5 * 86_400)
        XCTAssertEqual(
            policy.state(verifiedEntitlement: nil, priorUse: evidence(predates: false), trialStartedAt: started, now: now),
            .trial(daysRemaining: 1))
    }

    func testAVerifiedLicenceOutranksEverything() {
        let expiredTrial = now.addingTimeInterval(-100 * 86_400)
        XCTAssertEqual(
            policy.state(
                verifiedEntitlement: "founder", priorUse: evidence(predates: false),
                trialStartedAt: expiredTrial, now: now),
            .licensed(entitlement: "founder"))
    }

    // Three documents said three different prices. There is now one source, and
    // no subscription anywhere in it.
    func testTheOfferIsBuyOnceAndSaysWhatItCovers() {
        XCTAssertEqual(PressTalkOffer.founderPriceUSD, 20)
        XCTAssertEqual(PressTalkOffer.personalPriceUSD, 39)
        for summary in [PressTalkOffer.founderSummary, PressTalkOffer.personalSummary] {
            XCTAssertTrue(summary.contains("once"), summary)
            XCTAssertTrue(summary.contains("Every future Mac update"), summary)
            XCTAssertFalse(summary.lowercased().contains("/mo"), summary)
            // "Lifetime" promises a schedule nobody can keep. Including every
            // release costs nothing per customer; promising to keep producing
            // them is unbounded labour.
            XCTAssertFalse(summary.lowercased().contains("lifetime"), summary)
        }
        XCTAssertTrue(PressTalkOffer.updateDisclaimer.contains("not guaranteed"))
    }

    func testEveryStateReadsAsPlainEnglish() {
        let states: [EntitlementPolicy.State] = [
            .grandfathered, .licensed(entitlement: "founder"),
            .trial(daysRemaining: 7), .trialExpired,
        ]
        for state in states {
            let summary = PressTalkOffer.stateSummary(state)
            XCTAssertGreaterThan(summary.count, 20, "\(state): \(summary)")
            XCTAssertFalse(summary.lowercased().contains("subscription month"), summary)
        }
        XCTAssertTrue(PressTalkOffer.stateSummary(.trial(daysRemaining: 1)).contains("1 day left"))
        XCTAssertTrue(PressTalkOffer.stateSummary(.trial(daysRemaining: 2)).contains("2 days left"))
    }
}
