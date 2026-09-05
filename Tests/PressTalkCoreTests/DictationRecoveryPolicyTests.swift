import XCTest
@testable import PressTalkCore

final class DictationRecoveryPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ text: String, ageSeconds: TimeInterval = 0, failed: Bool = false)
        -> DictationRecoveryPolicy.Entry
    {
        DictationRecoveryPolicy.Entry(
            text: text, createdAt: now.addingTimeInterval(-ageSeconds), deliveryFailed: failed)
    }

    func testMostRecentComesFirst() {
        let policy = DictationRecoveryPolicy()
        var entries: [DictationRecoveryPolicy.Entry] = []
        entries = policy.inserting(entry("first"), into: entries, now: now)
        entries = policy.inserting(entry("second"), into: entries, now: now)
        XCTAssertEqual(entries.map(\.text), ["second", "first"])
    }

    // An undo, not a history feature: every extra entry is dictation sitting in
    // memory that nobody asked to keep.
    func testOlderEntriesFallOffTheEnd() {
        let policy = DictationRecoveryPolicy(maximumEntries: 3)
        var entries: [DictationRecoveryPolicy.Entry] = []
        for index in 1...6 {
            entries = policy.inserting(entry("entry \(index)"), into: entries, now: now)
        }
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.text), ["entry 6", "entry 5", "entry 4"])
    }

    // Someone who dictated a password an hour ago must not find it in a menu.
    func testExpiredEntriesAreDropped() {
        let policy = DictationRecoveryPolicy(maximumEntries: 5, expiry: 60)
        let entries = [entry("fresh", ageSeconds: 10), entry("stale", ageSeconds: 120)]
        XCTAssertEqual(policy.pruned(entries, now: now).map(\.text), ["fresh"])
    }

    func testInsertingAlsoPrunes() {
        let policy = DictationRecoveryPolicy(maximumEntries: 5, expiry: 60)
        let existing = [entry("stale", ageSeconds: 120)]
        let updated = policy.inserting(entry("new"), into: existing, now: now)
        XCTAssertEqual(updated.map(\.text), ["new"])
    }

    // An empty row in a recovery menu is worse than no row.
    func testBlankTranscriptsAreNotStored() {
        let policy = DictationRecoveryPolicy()
        XCTAssertTrue(policy.inserting(entry(""), into: [], now: now).isEmpty)
        XCTAssertTrue(policy.inserting(entry("   \n "), into: [], now: now).isEmpty)
    }

    func testMenuLabelIsOneTruncatedLine() {
        let policy = DictationRecoveryPolicy()
        let label = policy.menuLabel(for: entry("one\ntwo three"), characterLimit: 48)
        XCTAssertEqual(label, "one two three")

        let long = String(repeating: "x", count: 100)
        let truncated = policy.menuLabel(for: entry(long), characterLimit: 20)
        XCTAssertEqual(truncated.count, 20)
        XCTAssertTrue(truncated.hasSuffix("…"))
    }

    // A dictation that never reached its destination is the one most worth
    // getting back, so it says so.
    func testUndeliveredEntriesAreMarked() {
        let policy = DictationRecoveryPolicy()
        XCTAssertTrue(policy.menuLabel(for: entry("hello", failed: true)).contains("(not pasted)"))
        XCTAssertFalse(policy.menuLabel(for: entry("hello", failed: false)).contains("(not pasted)"))
    }

    func testStoredTextIsNeverTruncatedOnlyItsLabel() {
        let policy = DictationRecoveryPolicy()
        let long = String(repeating: "word ", count: 200)
        let stored = policy.inserting(entry(long), into: [], now: now)
        XCTAssertEqual(stored.first?.text, long)
    }
}

final class RetainedAudioPolicyTests: XCTestCase {
    private let policy = RetainedAudioPolicy(maximumSeconds: 120, expiry: 300)

    // The only reason to keep a recording is that a retry could still help.
    func testFailedRecognitionIsRetainedForRetry() {
        XCTAssertEqual(
            policy.disposition(recognitionSucceeded: false, capturedSeconds: 4),
            .retainForRetry)
    }

    func testSuccessfulRecognitionDropsTheAudioImmediately() {
        XCTAssertEqual(
            policy.disposition(recognitionSucceeded: true, capturedSeconds: 4),
            .discardRecognized)
        XCTAssertFalse(policy.shouldRetain(recognitionSucceeded: true, capturedSeconds: 4))
    }

    func testNothingCapturedMeansNothingToRetain() {
        XCTAssertEqual(
            policy.disposition(recognitionSucceeded: false, capturedSeconds: 0),
            .discardEmpty)
    }

    func testOverlongRecordingsAreNotHeld() {
        XCTAssertEqual(
            policy.disposition(recognitionSucceeded: false, capturedSeconds: 600),
            .discardExpired)
    }

    func testRetainedAudioExpires() {
        XCTAssertEqual(
            policy.disposition(recognitionSucceeded: false, capturedSeconds: 4, ageSeconds: 301),
            .discardExpired)
        XCTAssertTrue(
            policy.shouldRetain(recognitionSucceeded: false, capturedSeconds: 4, ageSeconds: 299))
    }
}
