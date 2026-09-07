import XCTest
@testable import PressTalkCore

final class AudioInputCrashBreakerTests: XCTestCase {
    private let breaker = AudioInputCrashBreaker()

    func testACompletedStartLeavesNothingToActOn() {
        XCTAssertEqual(breaker.evaluate(unfinishedAttempt: nil), .noAction)
    }

    func testAnUnfinishedAttemptRevertsToTheSystemDefault() {
        let outcome = breaker.evaluate(unfinishedAttempt: .init(
            deviceUID: "SHURE-MV7i-001", deviceName: "Shure MV7i"))
        XCTAssertTrue(outcome.revertToSystemDefault)
    }

    /// The whole value of the message is that it names the microphone, so a
    /// person can tell whether the app blamed the right thing.
    func testTheMessageNamesTheDeviceAndTheWayBack() {
        let outcome = breaker.evaluate(unfinishedAttempt: .init(
            deviceUID: "SHURE-MV7i-001", deviceName: "Shure MV7i"))
        let message = try! XCTUnwrap(outcome.userMessage)
        XCTAssertTrue(message.contains("Shure MV7i"), message)
        XCTAssertTrue(message.contains("Settings"), message)
    }

    /// A record with no UID cannot be attributed to any device. Reverting on it
    /// would take a microphone away on evidence that names nothing.
    func testARecordWithoutAUIDIsDiscardedWithoutReverting() {
        XCTAssertEqual(
            breaker.evaluate(unfinishedAttempt: .init(deviceUID: "", deviceName: "Shure MV7i")),
            .noAction)
        XCTAssertEqual(
            breaker.evaluate(unfinishedAttempt: .init(deviceUID: "   ", deviceName: "Shure MV7i")),
            .noAction)
    }

    /// A device can be unplugged between the crash and the next launch, so the
    /// name is not guaranteed. The revert still has to happen, and the sentence
    /// still has to read like English.
    func testAnUnnamedDeviceStillRevertsAndStillReads() {
        let outcome = breaker.evaluate(unfinishedAttempt: .init(
            deviceUID: "SHURE-MV7i-001", deviceName: ""))
        XCTAssertTrue(outcome.revertToSystemDefault)
        let message = try! XCTUnwrap(outcome.userMessage)
        XCTAssertFalse(message.contains("  "), "double space from an empty name: \(message)")
        XCTAssertTrue(message.contains("the microphone you chose"), message)
    }
}
