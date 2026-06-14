#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-transcript-text-policy-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

cp "$REPO_ROOT/Sources/PressTalkCore/TranscriptTextPolicy.swift" "$TEST_TMPDIR/TranscriptTextPolicy.swift"
cat > "$TEST_TMPDIR/main.swift" <<'SWIFT'
import Darwin
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let policy = TranscriptTextPolicy(shortHoldNoSpeechSuppressionSeconds: 1.5)

expect(policy.cleanedText("  hello   , world  ! ") == "hello, world!", "cleaning must normalize whitespace around punctuation")
expect(policy.cleanedText("[music]") == "", "wrapped non-speech direction must be suppressed")
expect(policy.cleanedText("This is fine. (coughing) Continue.") == "This is fine. Continue.", "inline non-speech direction must be removed")
expect(policy.cleanedText(",,, okay") == "okay", "leading punctuation noise must be removed")

expect(policy.normalizedPhrase("  Hello, WORLD! ") == "hello world", "normalized phrase must clean and tokenize")
expect(policy.tokens("Hello, WORLD!") == ["hello", "world"], "tokens must be lowercased alphanumerics")

expect(!policy.isPlausibleTranscript(""), "empty transcript must not be plausible")
expect(!policy.isPlausibleTranscript("Waiting for speech..."), "placeholder transcript must not be plausible")
expect(!policy.isPlausibleTranscript(",,, ..."), "punctuation-only transcript must not be plausible")
expect(!policy.isPlausibleTranscript("test test test test test test"), "highly repetitive transcript must not be plausible")
expect(policy.isPlausibleTranscript("Ja das will ich auch haben."), "normal German sentence must be plausible")

expect(
    policy.isLikelySilenceHallucination(
        "Thank you.",
        signalRMS: 0.0001,
        signalPeak: 0.001,
        captureDurationSeconds: 2.0
    ),
    "weak-audio thank-you hallucination must be suppressed"
)

expect(
    policy.isLikelySilenceHallucination(
        "Thanks",
        signalRMS: 0.1,
        signalPeak: 0.2,
        captureDurationSeconds: 0.8
    ),
    "short-hold thank-you hallucination must be suppressed"
)

expect(
    !policy.isLikelySilenceHallucination(
        "Thanks for the detailed update.",
        signalRMS: 0.1,
        signalPeak: 0.2,
        captureDurationSeconds: 3.0
    ),
    "real phrase containing thanks must not be suppressed"
)

expect(
    policy.bestTranscriptCandidate(from: ["[music]", "short", "This is the longer usable transcript."]) == "This is the longer usable transcript.",
    "best candidate must prefer the longest plausible cleaned transcript"
)
SWIFT

swiftc "$TEST_TMPDIR/TranscriptTextPolicy.swift" "$TEST_TMPDIR/main.swift" -o "$TEST_TMPDIR/transcript-text-policy-test"
"$TEST_TMPDIR/transcript-text-policy-test"

echo "PASS transcript_text_policy"
