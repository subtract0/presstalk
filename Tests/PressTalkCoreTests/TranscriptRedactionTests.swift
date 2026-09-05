import CryptoKit
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
        XCTAssertTrue(redacted.contains("run-digest="), redacted)
    }

    func testTheDigestDistinguishesTranscriptsWithinOneRun() {
        XCTAssertEqual(TranscriptRedaction.digest("hello"), TranscriptRedaction.digest("hello"))
        XCTAssertNotEqual(TranscriptRedaction.digest("hello"), TranscriptRedaction.digest("hallo"))
        XCTAssertEqual(TranscriptRedaction.digest("hello").count, 8)
    }

    // An unsalted hash of a short utterance is not redaction. "4827" has ten
    // thousand candidates, and people dictate PINs and phone numbers. The salt is
    // per process and discarded on exit, so the digest is useless to anyone
    // reading the log later.
    func testTheDigestIsNotAnOfflineGuessingTarget() {
        let plainSHA256 = SHA256.hash(data: Data("4827".utf8))
            .compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
        XCTAssertNotEqual(
            TranscriptRedaction.digest("4827"), plainSHA256,
            "the digest must not be a plain unsalted SHA-256 prefix")
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
