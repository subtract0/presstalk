import XCTest
@testable import PressTalkCore

/// Every MUST-REFUSE case here corresponds to the crash signature seen on
/// 2026-08-29, 08-30 and 09-03. Every MUST-ALLOW case guards against the worse
/// failure: a false positive would block dictation entirely.
final class AudioInputPreflightPolicyTests: XCTestCase {
    let policy = AudioInputPreflightPolicy()

    private func check(hw: Double, node: Double, ch: UInt32, buildable: Bool = true) -> String? {
        policy.failureReason(hardwareSampleRate: hw, nodeSampleRate: node,
                             nodeChannelCount: ch, canBuildTapFormat: buildable)
    }

    // MUST ALLOW — healthy devices must never be refused.
    func testAllowsMatchingFormats() {
        XCTAssertNil(check(hw: 48000, node: 48000, ch: 1))
        XCTAssertNil(check(hw: 44100, node: 44100, ch: 2))
        XCTAssertNil(check(hw: 24000, node: 24000, ch: 1))   // the live studio1 device
        XCTAssertNil(check(hw: 16000, node: 16000, ch: 1))
    }

    func testAllowsSubHertzJitter() {
        // Sample rates are Doubles; 48000 vs 48000.0000001 is not a fault.
        XCTAssertNil(check(hw: 48000.0000001, node: 48000, ch: 1))
        XCTAssertNil(check(hw: 44100.5, node: 44100, ch: 1))
    }

    // MUST REFUSE — these are what actually crashed the app.
    func testRefusesSampleRateMismatch() {
        let r = check(hw: 48000, node: 44100, ch: 1)
        XCTAssertNotNil(r)
        XCTAssertTrue(r!.contains("mismatch"), r ?? "")
        XCTAssertTrue(r!.contains("device likely changed"), r ?? "")
    }

    func testRefusesNoInputDevice() {
        XCTAssertNotNil(check(hw: 0, node: 0, ch: 0))
        XCTAssertTrue(check(hw: 0, node: 48000, ch: 1)!.contains("no usable input device"))
    }

    func testRefusesZeroChannels() {
        XCTAssertTrue(check(hw: 48000, node: 48000, ch: 0)!.contains("0 channels"))
    }

    func testRefusesUnbuildableTapFormat() {
        XCTAssertTrue(check(hw: 48000, node: 48000, ch: 1, buildable: false)!.contains("cannot build a tap format"))
    }

    func testRefusesNonFiniteRates() {
        XCTAssertNotNil(check(hw: .nan, node: 48000, ch: 1))
        XCTAssertNotNil(check(hw: .infinity, node: 48000, ch: 1))
        XCTAssertNotNil(check(hw: 48000, node: .nan, ch: 1))
    }

    // Ordering matters: a dead device must report as a dead device, not as a
    // "mismatch", or the message sends you chasing the wrong thing.
    func testDeadDeviceReportsAsDeadNotAsMismatch() {
        XCTAssertTrue(check(hw: 0, node: 44100, ch: 1)!.contains("no usable input device"))
    }
}
