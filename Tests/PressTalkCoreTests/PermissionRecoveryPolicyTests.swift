import XCTest
@testable import PressTalkCore

final class PermissionRecoveryPolicyTests: XCTestCase {
    private let policy = PermissionRecoveryPolicy()

    func testFreshDenialOffersSettingsWithoutAutomaticRecovery() {
        XCTAssertEqual(policy.state(for: .init(permissionAvailable: false)), .openSystemSettings)
    }

    func testOpeningSettingsIsNeitherAVisitCompletionNorAGrant() {
        let context = PermissionRecoveryPolicy.Context(
            permissionAvailable: false, hasOpenedSystemSettings: true)
        XCTAssertEqual(policy.state(for: context), .waitingForReturn)
    }

    func testReturningWithoutUsableAccessOffersOneRestart() {
        var context = PermissionRecoveryPolicy.Context(permissionAvailable: false,
            hasOpenedSystemSettings: true, hasReturnedFromSystemSettings: true)
        XCTAssertEqual(policy.state(for: context), .restartToRefresh)
        context.restartAttempted = true
        XCTAssertEqual(policy.state(for: context), .renewPermission)
    }

    func testConfirmedOldIdentitySkipsAnIneffectiveRestart() {
        let context = PermissionRecoveryPolicy.Context(permissionAvailable: false,
            identityMismatchConfirmed: true)
        XCTAssertEqual(policy.state(for: context), .renewPermission)
    }

    func testRenewalDoesNotPretendToGrantOrRepeatItself() {
        var context = PermissionRecoveryPolicy.Context(permissionAvailable: false,
            hasOpenedSystemSettings: true, hasReturnedFromSystemSettings: true,
            restartAttempted: true, permissionRenewalAttempted: true,
            identityMismatchConfirmed: true)
        XCTAssertEqual(policy.state(for: context), .systemApprovalRequired)
        // More activation/poll events cannot lead to another reset or restart.
        for _ in 0..<5 {
            context.hasReturnedFromSystemSettings = true
            XCTAssertEqual(policy.state(for: context), .systemApprovalRequired)
        }
    }

    func testAnyRecoveryWaitsForCaptureAndDeliveryToFinish() {
        for context in [
            PermissionRecoveryPolicy.Context(permissionAvailable: false),
            .init(permissionAvailable: false, hasOpenedSystemSettings: true,
                  hasReturnedFromSystemSettings: true),
            .init(permissionAvailable: false, restartAttempted: true),
            .init(permissionAvailable: false, permissionRenewalAttempted: true),
            .init(permissionAvailable: false, identityMismatchConfirmed: true),
        ] {
            var busy = context
            busy.recordingOrProcessing = true
            XCTAssertEqual(policy.state(for: busy), .finishCurrentDictation)
        }
    }

    func testActualGrantWinsOverOldFailureAndRecoveryHistory() {
        let context = PermissionRecoveryPolicy.Context(permissionAvailable: true,
            hasOpenedSystemSettings: true, hasReturnedFromSystemSettings: true,
            restartAttempted: true, permissionRenewalAttempted: true,
            identityMismatchConfirmed: true, recordingOrProcessing: true)
        XCTAssertEqual(policy.state(for: context), .ready)
    }

    func testInconsistentReturnEventDoesNotSkipTheInitialUserAction() {
        XCTAssertEqual(policy.state(for: .init(permissionAvailable: false,
            hasReturnedFromSystemSettings: true)), .openSystemSettings)
    }
}
