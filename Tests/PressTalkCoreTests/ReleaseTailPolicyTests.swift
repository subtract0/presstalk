import XCTest
@testable import PressTalkCore

/// Reported from daily use: talk, pause about a second, say one short closing
/// sentence, release -- and the closing sentence is missing.
final class ReleaseTailPolicyTests: XCTestCase {

    /// `stalledFor` defaults to a single poll interval: the ordinary case,
    /// where the tap simply has not delivered its next 0.1 s buffer yet.
    private func inputs(elapsed: Double, captured: Double, expected: Double,
                        rms: Double, stalledFor: Double = 0.025)
    -> ReleaseTailPolicy.Inputs {
        .init(elapsedSeconds: elapsed, capturedSeconds: captured,
              expectedAtReleaseSeconds: expected, recentRMS: rms,
              secondsSinceCapturedGrew: stalledFor)
    }

    private func decide(_ i: ReleaseTailPolicy.Inputs,
                        max: Double = 0.35) -> ReleaseTailPolicy.Decision {
        ReleaseTailPolicy.decide(i, maximumSeconds: max)
    }

    // MARK: one silent poll is not a dead microphone

    /// Real values from the trace, 2026-09-07: expected 3.52 s at release,
    /// 3.40 s captured, 0.11 s elapsed, and no growth in the most recent poll.
    /// The old rule read that single quiet poll as a dead tap and stopped,
    /// discarding 120 ms of speech still in flight -- and it did so on 11 of
    /// the 13 tails in that log.
    ///
    /// The tap delivers one buffer per 0.1 s while this polls every 0.025 s, so
    /// three polls in four see no growth in perfectly healthy capture. The
    /// signal was never evidence of anything.
    func testASinglePollWithoutGrowthIsNotADeadStream() {
        let decision = decide(inputs(
            elapsed: 0.11, captured: 3.40, expected: 3.52, rms: 0.0005,
            stalledFor: 0.025))
        XCTAssertFalse(decision.shouldStop, "stopped on one quiet poll")
        XCTAssertEqual(decision.reason, "audio_still_in_flight")
    }

    /// Nor are two or three of them, which is the ordinary gap between buffers.
    func testAWholeBufferIntervalWithoutGrowthStillWaits() {
        for stalled in [0.05, 0.10, 0.20] {
            let decision = decide(inputs(
                elapsed: 0.15, captured: 3.40, expected: 3.52, rms: 0.0005,
                stalledFor: stalled))
            XCTAssertFalse(decision.shouldStop,
                           "stopped after only \(stalled)s without growth")
        }
    }

    /// The protection that must survive: a tap that has genuinely stopped
    /// delivering should not hold the tail open to its maximum, because that
    /// adds latency to a capture that is already broken.
    func testATrulyStalledTapStillStops() {
        let decision = decide(inputs(
            elapsed: 0.30, captured: 3.40, expected: 3.52, rms: 0.0005,
            stalledFor: 0.30))
        XCTAssertTrue(decision.shouldStop)
        XCTAssertEqual(decision.reason, "no_further_audio")
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
            stalledFor: 0.4))
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
