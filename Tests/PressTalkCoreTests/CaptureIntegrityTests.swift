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
            capturedSeconds: 0.7, heldSeconds: 0.9, rms: 0.02, peak: 0.3).isUsable)
    }

    /// This used to assert that 0.9 s captured from a 2.9 s hold was fine,
    /// because the truncation check began at 3 s. It is not fine: two thirds of
    /// what was said is gone. The real case was 0.30 s from a 2.75 s hold after
    /// 2.4 s of engine startup, reported to the owner as ordinary silence.
    func testLosingMostOfAShortButDeliberateHoldIsTruncation() {
        XCTAssertEqual(
            CaptureIntegrity.evaluate(capturedSeconds: 0.9, heldSeconds: 2.9,
                                      rms: 0.02, peak: 0.3),
            .truncated(capturedSeconds: 0.9, heldSeconds: 2.9))
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
                                 peak: Double = 0.0) -> Bool {
        policy.isLikelySilenceHallucination(text, signalRMS: rms, signalPeak: peak)
    }

    /// Speech energy, in the range this Mac's own trace logs show for real
    /// dictation: RMS 0.027-0.060 with peaks of 0.15-0.42.
    private func isHallucinationOnClearSpeech(_ text: String) -> Bool {
        policy.isLikelySilenceHallucination(text, signalRMS: 0.04, signalPeak: 0.30)
    }

    // MARK: - Regressions found in review, reproduced exactly

    /// One sample at 0.1 in an otherwise silent second: RMS 0.00079, peak 0.1.
    /// The gate was `rms < 0.0035 && peak < 0.045`, so the single transient
    /// read as "not weak" and the denylist was bypassed entirely -- a click in
    /// silence was enough to let an invented "Thanks" through.
    func testATransientInSilenceDoesNotDefeatTheGate() {
        let rms = 0.000790569, peak = 0.1
        XCTAssertTrue(isHallucination("Thanks", rms: rms, peak: peak))
        XCTAssertTrue(isHallucination("you you", rms: rms, peak: peak))
        XCTAssertTrue(isHallucination("Thank you.", rms: rms, peak: peak))
    }

    /// "Nobody says a word three times" is plainly false. Emphatic repetition
    /// is ordinary speech, and an unbounded loop rule threw it away.
    func testEmphaticRepetitionIsSpeechNotALoop() {
        XCTAssertFalse(isHallucinationOnClearSpeech("Nein, nein, nein!"))
        XCTAssertFalse(isHallucinationOnClearSpeech("nein nein nein"))
        XCTAssertFalse(isHallucinationOnClearSpeech("ja ja ja"))
    }

    /// The protection that had to survive narrowing that rule: a decoder
    /// looping on a known stem is still caught however loud the audio is.
    func testALoopOnAKnownStemIsStillCaughtOnLoudAudio() {
        XCTAssertTrue(isHallucinationOnClearSpeech("you you you"))
        XCTAssertTrue(isHallucinationOnClearSpeech("thanks thanks thanks"))
    }

    // MARK: - Short replies are speech, not silence

    /// The defect: the rejection path was entered on `weakAudio || shortCapture`,
    /// so a short hold went to the denylist however loud it was -- and the
    /// denylist contains "danke", "okay", "vielen dank", "bye" and "so".
    /// Answering a message with "Danke" produced nothing at all, silently.
    func testOrdinaryShortRepliesSurviveClearAudio() {
        for reply in ["danke", "okay", "vielen dank", "bye", "so", "thanks",
                      "Danke!", "Okay.", "Vielen Dank"] {
            XCTAssertFalse(isHallucinationOnClearSpeech(reply),
                           "\(reply) was discarded as a hallucination")
        }
    }

    /// German reduplication is a real answer, not a decoder loop. Two repeats
    /// used to be treated as looping, which ate "ja ja" and "nein nein".
    func testDoubledGermanAnswersSurviveClearAudio() {
        XCTAssertFalse(isHallucinationOnClearSpeech("ja ja"))
        XCTAssertFalse(isHallucinationOnClearSpeech("nein nein"))
    }

    /// The protection that must NOT be lost with it: a decoder repeating one
    /// token three or more times is looping whatever the audio level says.
    func testALoopingDecoderIsStillCaughtOnLoudAudio() {
        XCTAssertTrue(isHallucinationOnClearSpeech("you you you"))
        XCTAssertTrue(isHallucinationOnClearSpeech("danke danke danke danke"))
    }

    /// And the denylist still applies with full force when the audio really is
    /// weak, at any duration. Dropping the duration term must not have widened
    /// the door for silence.
    func testTheDenylistStillHoldsOnWeakAudioOfAnyLength() {
        for reply in ["danke", "okay", "vielen dank", "you", "bye"] {
            XCTAssertTrue(isHallucination(reply, rms: 0.001, peak: 0.01),
                          "\(reply) escaped on weak audio")
        }
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
            rms: 0.029, peak: 0.34))
        // Short but genuine, over a real signal.
        XCTAssertFalse(isHallucination("Ja, passt.", rms: 0.02, peak: 0.25))
    }

    /// Someone may genuinely dictate the word "you" into a working microphone.
    func testAListedWordOverGoodAudioIsNotRejected() {
        XCTAssertFalse(isHallucination("you", rms: 0.03, peak: 0.35))
        XCTAssertFalse(isHallucination("thank you", rms: 0.03, peak: 0.35))
    }
}

/// Measured on studio1, 2026-09-07: AirPods take about 1.2 s to start where the
/// USB Shure takes 0.33 s. The owner described it independently as "5-7
/// syllables cut off", which is what 1.2 s of speech is.
final class LateStartTests: XCTestCase {

    func testABluetoothStartIsReportedAsLost() {
        let verdict = CaptureIntegrity.evaluate(
            capturedSeconds: 6.6, heldSeconds: 7.0, rms: 0.02, peak: 0.3,
            engineStartSeconds: 1.222)
        XCTAssertEqual(verdict, .startedLate(lostSeconds: 1.222))
        XCTAssertTrue((verdict.userFacingMessage ?? "").contains("1.2"))
    }

    /// The text still gets delivered. Refusing a recording because it began
    /// late would throw away a sentence the person did say.
    func testALateStartIsStillUsable() {
        XCTAssertTrue(CaptureIntegrity.evaluate(
            capturedSeconds: 6.6, heldSeconds: 7.0, rms: 0.02, peak: 0.3,
            engineStartSeconds: 1.222).isUsable)
    }

    /// A USB microphone starts fast enough that nobody notices, and must not be
    /// apologised for.
    func testAFastStartSaysNothing() {
        XCTAssertEqual(
            CaptureIntegrity.evaluate(capturedSeconds: 5.0, heldSeconds: 5.2,
                                      rms: 0.02, peak: 0.3, engineStartSeconds: 0.327),
            .usable)
    }

    /// Losing most of the hold is the bigger failure and keeps the message.
    func testTruncationOutranksALateStart() {
        XCTAssertEqual(
            CaptureIntegrity.evaluate(capturedSeconds: 0.3, heldSeconds: 2.75,
                                      rms: 0.02, peak: 0.3, engineStartSeconds: 2.4),
            .truncated(capturedSeconds: 0.3, heldSeconds: 2.75))
    }
}
