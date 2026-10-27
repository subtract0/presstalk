import Foundation
import XCTest
@testable import PressTalkCore

final class UpdateSafetyPolicyTests: XCTestCase {
    func testEveryActiveOperationDefersInstallation() {
        let idle = UpdateSafetyPolicy.Activity()
        XCTAssertFalse(idle.isBusy)
        for activity in [
            UpdateSafetyPolicy.Activity(isRecording: true),
            .init(isProcessing: true), .init(isMicrophoneProbeRunning: true),
            .init(isCalibrationRunning: true), .init(isPermissionRenewalRunning: true),
            .init(isCapturePending: true),
            .init(isClipboardRestoring: true),
        ] {
            XCTAssertTrue(activity.isBusy)
        }
    }

    func testOnlyOfficialSignedConfiguredAppIsEligible() {
        func eligible(
            identifier: String? = "com.am.presstalk", app: Bool = true, signature: Bool = true,
            feed: String? = "https://presstalk.app/appcast.xml",
            key: String? = Data(repeating: 7, count: 32).base64EncodedString(),
            signedFeed: Bool = true, verify: Bool = true
        ) -> Bool {
            UpdateSafetyPolicy.isEligible(bundleIdentifier: identifier, isApplicationBundle: app,
                hasValidProductionSignature: signature, feedURL: feed, publicKey: key,
                requiresSignedFeed: signedFeed, verifiesBeforeExtraction: verify)
        }
        XCTAssertTrue(eligible())
        XCTAssertFalse(eligible(identifier: "com.am.presstalk.dev"))
        XCTAssertFalse(eligible(identifier: nil))
        XCTAssertFalse(eligible(app: false))
        XCTAssertFalse(eligible(signature: false))
        XCTAssertFalse(eligible(feed: "http://presstalk.app/appcast.xml"))
        XCTAssertFalse(eligible(feed: "https://example.com/appcast.xml"))
        XCTAssertFalse(eligible(key: nil))
        XCTAssertFalse(eligible(key: "invalid"))
        XCTAssertFalse(eligible(key: Data(repeating: 0, count: 31).base64EncodedString()))
        XCTAssertFalse(eligible(signedFeed: false))
        XCTAssertFalse(eligible(verify: false))
    }

    @MainActor func testContinuationWaitsForAtomicReservationAndRunsOnce() {
        var busy = true, reserved = false
        var invocations = 0, releases = 0
        let gate = UpdateInstallationGate(tryReserve: {
            guard !busy && !reserved else { return false }
            reserved = true
            return true
        }, release: { reserved = false; releases += 1 })
        gate.postpone {
            XCTAssertTrue(reserved)
            XCTAssertEqual(gate.state, .installing)
            invocations += 1
        }
        XCTAssertFalse(gate.resumeWhenSafe())
        XCTAssertEqual(gate.state, .waitingForIdle)
        XCTAssertEqual(invocations, 0)
        busy = false
        XCTAssertTrue(gate.resumeWhenSafe())
        XCTAssertFalse(gate.resumeWhenSafe())
        XCTAssertEqual(invocations, 1)
        XCTAssertTrue(reserved)
        XCTAssertEqual(releases, 0)
        gate.cancel()
        gate.cancel()
        XCTAssertEqual(releases, 1)
        XCTAssertFalse(reserved)
    }

    @MainActor func testCancellationWhileBusyDiscardsContinuationWithoutReleasingUnownedReservation() {
        var invocations = 0, releases = 0
        let gate = UpdateInstallationGate(tryReserve: { false }, release: { releases += 1 })
        gate.postpone { invocations += 1 }
        gate.cancel()
        XCTAssertFalse(gate.resumeWhenSafe())
        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(releases, 0)
        XCTAssertEqual(gate.state, .idle)
    }

    @MainActor func testSynchronousInstallationAbortReleasesReservationAndCanRetry() {
        var reserved = false, invocations = 0
        let gate = UpdateInstallationGate(tryReserve: { reserved = true; return true },
                                          release: { reserved = false })
        gate.postpone { invocations += 1; gate.cancel() }
        XCTAssertTrue(gate.resumeWhenSafe())
        XCTAssertFalse(reserved)
        XCTAssertEqual(gate.state, .idle)
        gate.postpone { invocations += 1 }
        XCTAssertTrue(gate.resumeWhenSafe())
        XCTAssertEqual(invocations, 2)
        XCTAssertTrue(reserved)
        gate.cancel()
    }

    @MainActor func testReentrantContinuationDoesNotAcquireOrReleaseReservationTwice() {
        var reservations = 0, releases = 0, invocations = 0
        let gate = UpdateInstallationGate(tryReserve: { reservations += 1; return true },
                                          release: { releases += 1 })
        gate.postpone {
            invocations += 1
            gate.postpone { invocations += 1 }
        }
        XCTAssertTrue(gate.resumeWhenSafe())
        XCTAssertTrue(gate.resumeWhenSafe())
        XCTAssertEqual(invocations, 2)
        XCTAssertEqual(reservations, 1)
        XCTAssertEqual(releases, 0)
        gate.cancel()
        XCTAssertEqual(releases, 1)
    }
}
