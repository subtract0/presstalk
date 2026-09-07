import XCTest
@testable import PressTalkCore

final class TranscriptFallbackTests: XCTestCase {
    private enum Failure: Error, Equatable { case primaryUnavailable }

    func testSilenceWithOptionalWhisperAbsentReturnsNoTranscript() throws {
        XCTAssertEqual(try TranscriptFallback.withoutSecondary(
            acceptedPrimary: nil, acceptedStreaming: nil, primary: .completed
        ), "")
    }

    func testPrimaryFailureIsNotDisguisedAsSilence() {
        XCTAssertThrowsError(try TranscriptFallback.withoutSecondary(
            acceptedPrimary: nil, acceptedStreaming: nil,
            primary: .failed(Failure.primaryUnavailable)
        )) { XCTAssertEqual($0 as? Failure, .primaryUnavailable) }
    }

    func testNoRecognizerRunStillRequiresABackend() throws {
        XCTAssertNil(try TranscriptFallback.withoutSecondary(
            acceptedPrimary: nil, acceptedStreaming: nil, primary: .notAttempted
        ))
    }

    func testAcceptedPrimaryKeepsPriorityOverStreaming() throws {
        XCTAssertEqual(try TranscriptFallback.withoutSecondary(
            acceptedPrimary: "First through lighthouse.",
            acceptedStreaming: "First through", primary: .completed
        ), "First through lighthouse.")
    }

    func testStreamingCanRecoverAPrimaryFailure() throws {
        XCTAssertEqual(try TranscriptFallback.withoutSecondary(
            acceptedPrimary: nil, acceptedStreaming: "The complete sentence.",
            primary: .failed(Failure.primaryUnavailable)
        ), "The complete sentence.")
    }

    func testAcceptedShortSpeechIsPreserved() throws {
        XCTAssertEqual(try TranscriptFallback.withoutSecondary(
            acceptedPrimary: "Yes.", acceptedStreaming: nil, primary: .completed
        ), "Yes.")
    }
}
