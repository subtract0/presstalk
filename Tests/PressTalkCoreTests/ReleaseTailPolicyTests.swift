import XCTest
@testable import PressTalkCore

/// Reported from daily use: talk, pause about a second, say one short closing
/// sentence, release -- and the closing sentence is missing.
final class ReleaseTailPolicyTests: XCTestCase {

    private func inputs(elapsed: Double, captured: Double, expected: Double,
                        rms: Double, growing: Bool = true) -> ReleaseTailPolicy.Inputs {
        .init(elapsedSeconds: elapsed, capturedSeconds: captured,
              expectedAtReleaseSeconds: expected, recentRMS: rms,
              capturedGrewSinceLastPoll: growing)
    }

    private func decide(_ i: ReleaseTailPolicy.Inputs,
                        max: Double = 0.35) -> ReleaseTailPolicy.Decision {
        ReleaseTailPolicy.decide(i, maximumSeconds: max)
    }

    // MARK: the reported bug

    /// The exact old behaviour: 0.11 s after release, the last delivered window
    /// is the pause before the closing sentence, so it measures as silence --
    /// while 0.15 s of speech is still in the pipeline.
    func testDoesNotStopWhileTheClosingSentenceIsStillInFlight() {
        let decision = decide(inputs(
            elapsed: 0.11, captured: 11.55, expected: 11.70, rms: 0.0005))
        XCTAssertFalse(decision.shouldStop)
        XCTAssertEqual(decision.reason, "audio_still_in_flight")
    }

    /// And once it has caught up, quiet genuinely means finished.
    func testStopsOnceTheRecordingHasCaughtUpAndIsQuiet() {
        let decision = decide(inputs(
            elapsed: 0.20, captured: 11.70, expected: 11.70, rms: 0.0005))
        XCTAssertTrue(decision.shouldStop)
        XCTAssertEqual(decision.reason, "silence_after_catch_up")
    }

    /// Real numbers from the trace: every capture exited at 0.10-0.11 s with an
    /// RMS around 0.0005 and lost 0.1-0.15 s of audio. All of them now wait.
    func testEveryObservedEarlyExitNowWaits() {
        for (captured, expected, rms) in [(3.90, 4.05, 0.00064),
                                          (10.00, 10.15, 0.00176),
                                          (17.80, 17.95, 0.00161),
                                          (7.90, 8.08, 0.00065)] {
            let decision = decide(inputs(
                elapsed: 0.11, captured: captured, expected: expected, rms: rms))
            XCTAssertFalse(decision.shouldStop,
                           "captured \(captured) of \(expected) should keep waiting")
        }
    }

    // MARK: not making every dictation slower

    /// A capture already level with the key stops at the minimum, exactly as
    /// before. Most dictations end with the speaker trailing off, and adding
    /// latency to all of them to rescue a rarer case would be a bad trade.
    func testACaughtUpQuietCaptureStillStopsAtTheMinimum() {
        let decision = decide(inputs(
            elapsed: 0.10, captured: 5.00, expected: 5.00, rms: 0.0003))
        XCTAssertTrue(decision.shouldStop)
    }

    func testStillSpeakingKeepsWaiting() {
        XCTAssertFalse(decide(inputs(
            elapsed: 0.15, captured: 5.00, expected: 5.00, rms: 0.08)).shouldStop)
    }

    func testTheMinimumIsAlwaysHonoured() {
        XCTAssertFalse(decide(inputs(
            elapsed: 0.05, captured: 5.0, expected: 5.0, rms: 0.0)).shouldStop)
    }

    // MARK: bounded, always

    /// The maximum wins over everything. Without this a capture that never
    /// converges would hold the tail open and the user would wait.
    func testTheMaximumStopsEvenWhileAudioIsInFlight() {
        let decision = decide(inputs(
            elapsed: 0.35, captured: 5.00, expected: 9.00, rms: 0.09), max: 0.35)
        XCTAssertTrue(decision.shouldStop)
        XCTAssertEqual(decision.reason, "max_tail")
    }

    /// A dead tap delivers nothing. Waiting for audio that will never arrive
    /// only adds latency to a capture that has already failed.
    func testStopsWhenNoFurtherAudioIsArriving() {
        let decision = decide(inputs(
            elapsed: 0.15, captured: 1.70, expected: 37.20, rms: 0.0,
            growing: false))
        XCTAssertTrue(decision.shouldStop)
        XCTAssertEqual(decision.reason, "no_further_audio")
    }

    /// Small slack, so a capture that converges to within a tap buffer is not
    /// held open chasing the last few milliseconds.
    func testASmallShortfallCountsAsCaughtUp() {
        let decision = decide(inputs(
            elapsed: 0.12, captured: 9.97, expected: 10.00, rms: 0.0004))
        XCTAssertTrue(decision.shouldStop)
        XCTAssertEqual(decision.reason, "silence_after_catch_up")
    }

    /// Captured can exceed expected -- the tail is recording past the release.
    /// That must read as caught up, not as a negative shortfall bug.
    func testCapturingPastTheReleaseIsCaughtUp() {
        XCTAssertTrue(decide(inputs(
            elapsed: 0.20, captured: 10.30, expected: 10.00, rms: 0.0004)).shouldStop)
    }
}
