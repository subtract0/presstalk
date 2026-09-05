import XCTest
@testable import PressTalkCore

final class TranscriptRedactionTests: XCTestCase {
    private let secret = "Mein Passwort ist Hunter2 und die Kontonummer endet auf 4471"

    func testRedactedFormContainsNoneOfTheWords() {
        let redacted = TranscriptRedaction.redacted(secret)
        for word in secret.split(separator: " ") {
            XCTAssertFalse(redacted.contains(word), "redacted output leaked \(word): \(redacted)")
        }
    }

    // The redaction has to stay useful for debugging or people will turn it off.
    func testRedactedFormKeepsWhatDebuggingNeeds() {
        let redacted = TranscriptRedaction.redacted(secret)
        XCTAssertTrue(redacted.contains("chars=\(secret.count)"), redacted)
        XCTAssertTrue(redacted.contains("words=10"), redacted)
        XCTAssertTrue(redacted.contains("digest="), redacted)
    }

    func testTheDigestDistinguishesTranscriptsWithoutRevealingThem() {
        XCTAssertEqual(TranscriptRedaction.digest("hello"), TranscriptRedaction.digest("hello"))
        XCTAssertNotEqual(TranscriptRedaction.digest("hello"), TranscriptRedaction.digest("hallo"))
        XCTAssertEqual(TranscriptRedaction.digest("hello").count, 8)
    }

    func testEmptyTranscriptsAreLabelledNotDigested() {
        XCTAssertEqual(TranscriptRedaction.redacted(""), "<empty>")
        XCTAssertEqual(TranscriptRedaction.redacted("   \n "), "<empty>")
    }

    // Redaction is what happens unless someone deliberately turned it off.
    func testLoggingIsRedactedByDefault() {
        XCTAssertEqual(TranscriptRedaction.loggable(secret, environment: [:]),
                       TranscriptRedaction.redacted(secret))
        XCTAssertEqual(TranscriptRedaction.loggable(secret, environment: ["PRESSTALK_LOG_TRANSCRIPTS": "0"]),
                       TranscriptRedaction.redacted(secret))
    }

    func testTheOptInIsExplicit() {
        for value in ["1", "true", "yes", "TRUE"] {
            XCTAssertEqual(
                TranscriptRedaction.loggable(secret, environment: ["PRESSTALK_LOG_TRANSCRIPTS": value]),
                secret, "\(value) should enable verbose logging")
        }
        for value in ["", "0", "no", "maybe", "2"] {
            XCTAssertNotEqual(
                TranscriptRedaction.loggable(secret, environment: ["PRESSTALK_LOG_TRANSCRIPTS": value]),
                secret, "\(value) should not enable verbose logging")
        }
    }
}
