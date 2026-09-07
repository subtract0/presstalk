#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-transcript-text-policy-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

cp "$REPO_ROOT/Sources/PressTalkCore/TranscriptTextPolicy.swift" "$TEST_TMPDIR/TranscriptTextPolicy.swift"
# CaptureIntegrity too: the policy reads its silence floor, so compiling the
# policy alone failed with "cannot find CaptureIntegrity in scope". A gate that
# cannot compile is a gate that is not running, and this one had stopped.
cp "$REPO_ROOT/Sources/PressTalkCore/CaptureIntegrity.swift" "$TEST_TMPDIR/CaptureIntegrity.swift"
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
        signalPeak: 0.001
    ),
    "weak-audio thank-you hallucination must be suppressed"
)

// Inverted deliberately on 2026-09-07. This used to assert that a LOUD, CLEAR
// "Thanks" is a hallucination purely because the hold was short, and that is
// the defect, not the guard: someone answering a message with "Thanks" or
// "Danke" got silence and no error. Measured across 1,624 captures in this
// Mac's trace logs, short captures that are genuinely silent sit at RMS 0.00047
// and are already caught by the weak-audio test; the duration term only cost
// the 70 real short utterances carrying RMS 0.027-0.060.
expect(
    !policy.isLikelySilenceHallucination(
        "Thanks",
        signalRMS: 0.1,
        signalPeak: 0.2
    ),
    "a short reply over clear audio must be delivered, not suppressed"
)

expect(
    policy.isLikelySilenceHallucination(
        "Thanks",
        signalRMS: 0.0005,
        signalPeak: 0.004
    ),
    "the same word over weak audio must still be suppressed"
)

expect(
    policy.isLikelySilenceHallucination(
        "you you you",
        signalRMS: 0.1,
        signalPeak: 0.2
    ),
    "a decoder looping on one token must be caught at any audio level"
)

expect(
    !policy.isLikelySilenceHallucination(
        "Thanks for the detailed update.",
        signalRMS: 0.1,
        signalPeak: 0.2
    ),
    "real phrase containing thanks must not be suppressed"
)

expect(
    policy.bestTranscriptCandidate(from: ["[music]", "short", "This is the longer usable transcript."]) == "This is the longer usable transcript.",
    "best candidate must prefer the longest plausible cleaned transcript"
)
SWIFT

swiftc "$TEST_TMPDIR/TranscriptTextPolicy.swift" "$TEST_TMPDIR/CaptureIntegrity.swift" "$TEST_TMPDIR/main.swift" -o "$TEST_TMPDIR/transcript-text-policy-test"
"$TEST_TMPDIR/transcript-text-policy-test"

echo "PASS transcript_text_policy"
