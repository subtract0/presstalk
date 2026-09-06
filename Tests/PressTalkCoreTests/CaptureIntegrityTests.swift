import XCTest
@testable import PressTalkCore

/// The failure these exist for: 37.2 seconds held, 1.7 seconds captured, every
/// sample zero, and "you you" pasted into a chat window.
final class CaptureIntegrityTests: XCTestCase {

    // MARK: the actual incident

    func testTheRealFailureIsCaught() {
        let verdict = CaptureIntegrity.evaluate(
            capturedSeconds: 1.70, heldSeconds: 37.20, rms: 0.0, peak: 0.0)
        XCTAssertEqual(verdict, .silent)
        XCTAssertFalse(verdict.isUsable)
        XCTAssertNotNil(verdict.userFacingMessage)
    }

    /// Silence is named before truncation. Both were true in the incident, and
    /// "check your microphone" is the useful half.
    func testSilenceIsReportedRatherThanTruncation() {
        XCTAssertEqual(
            CaptureIntegrity.evaluate(
                capturedSeconds: 1.0, heldSeconds: 30.0, rms: 0.0, peak: 0.0),
            .silent)
    }

    // MARK: truncation

    func testLosingMostOfADeliberateHoldIsTruncation() {
        let verdict = CaptureIntegrity.evaluate(
            capturedSeconds: 2.0, heldSeconds: 20.0, rms: 0.02, peak: 0.3)
        XCTAssertEqual(verdict, .truncated(capturedSeconds: 2.0, heldSeconds: 20.0))
    }

    /// Some loss is normal: the engine takes time to start and the last buffer
    /// arrives after release. A gate that fires on that gets switched off.
    func testNormalStartupLossIsUsable() {
        // 0.17 s engine start on a 10 s hold, which is what a healthy machine does.
        XCTAssertTrue(CaptureIntegrity.evaluate(
            capturedSeconds: 9.8, heldSeconds: 10.0, rms: 0.02, peak: 0.3).isUsable)
        // Even a slow start leaves most of the hold intact.
        XCTAssertTrue(CaptureIntegrity.evaluate(
            capturedSeconds: 8.3, heldSeconds: 10.0, rms: 0.02, peak: 0.3).isUsable)
    }

    /// A stray tap of the Fn key is not a broken microphone, and must not be
    /// reported as one.
    func testShortTapsAreNotJudgedForTruncation() {
        XCTAssertTrue(CaptureIntegrity.evaluate(
            capturedSeconds: 0.1, heldSeconds: 0.4, rms: 0.02, peak: 0.3).isUsable)
        XCTAssertTrue(CaptureIntegrity.evaluate(
            capturedSeconds: 0.9, heldSeconds: 2.9, rms: 0.02, peak: 0.3).isUsable)
    }

    // MARK: not over-firing on real quiet speech

    /// A quiet room on a condenser microphone measures well above the floor.
    /// Treating that as silence would refuse genuine dictation.
    func testQuietButRealSpeechIsUsable() {
        XCTAssertTrue(CaptureIntegrity.evaluate(
            capturedSeconds: 10.0, heldSeconds: 10.2,
            rms: 0.00229, peak: 0.03).isUsable)
    }

    func testTheMessageNamesTheMicrophoneNotTheSpeaker() {
        let message = CaptureIntegrity.evaluate(
            capturedSeconds: 1.7, heldSeconds: 37.2, rms: 0, peak: 0).userFacingMessage
        XCTAssertNotNil(message)
        XCTAssertTrue(message!.lowercased().contains("microphone"))
        // It must not tell someone to speak more clearly when nothing was heard.
        XCTAssertFalse(message!.lowercased().contains("clear speech"))
    }

    func testUsableCarriesNoMessage() {
        XCTAssertNil(CaptureIntegrity.evaluate(
            capturedSeconds: 10, heldSeconds: 10, rms: 0.02, peak: 0.3).userFacingMessage)
    }
}

/// The denylist that lost to its own retry ladder.
final class SilenceHallucinationTests: XCTestCase {
    private let policy = TranscriptTextPolicy()

    private func isHallucination(_ text: String, rms: Double = 0.0,
                                 peak: Double = 0.0, seconds: Double = 1.7) -> Bool {
        policy.isLikelySilenceHallucination(
            text, signalRMS: rms, signalPeak: peak, captureDurationSeconds: seconds)
    }

    /// The exact escape: "you" was rejected, that rejection triggered the
    /// relaxed retry, and the retry's "you you" was not in the list.
    func testTheVariantThatEscaped() {
        XCTAssertTrue(isHallucination("you"))
        XCTAssertTrue(isHallucination("you you"))
        XCTAssertTrue(isHallucination("you you you"))
        XCTAssertTrue(isHallucination("You you."))
    }

    /// On genuinely dead audio nothing is acceptable, whatever it says. This is
    /// what makes the list stop being load-bearing.
    func testAnythingFromDigitalSilenceIsRejected() {
        XCTAssertTrue(isHallucination("Bitte schick mir die Unterlagen bis Donnerstag.",
                                      rms: 0.0, peak: 0.0))
        XCTAssertTrue(isHallucination("arbitrary words a decoder invented",
                                      rms: 0.0, peak: 0.0))
    }

    func testRepeatedSingleWordIsADecoderLoop() {
        XCTAssertTrue(isHallucination("okay okay okay", rms: 0.001, peak: 0.02))
        XCTAssertTrue(isHallucination("danke danke", rms: 0.001, peak: 0.02))
    }

    /// Real speech over real audio must survive, or the app refuses to work.
    func testRealSpeechOverRealAudioSurvives() {
        XCTAssertFalse(isHallucination(
            "Ich schicke dir die Unterlagen heute Abend.",
            rms: 0.029, peak: 0.34, seconds: 11.7))
        // Short but genuine, over a real signal.
        XCTAssertFalse(isHallucination("Ja, passt.", rms: 0.02, peak: 0.25, seconds: 2.0))
    }

    /// Someone may genuinely dictate the word "you" into a working microphone.
    func testAListedWordOverGoodAudioIsNotRejected() {
        XCTAssertFalse(isHallucination("you", rms: 0.03, peak: 0.35, seconds: 4.0))
        XCTAssertFalse(isHallucination("thank you", rms: 0.03, peak: 0.35, seconds: 4.0))
    }
}
