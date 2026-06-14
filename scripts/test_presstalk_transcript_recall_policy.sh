#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-transcript-recall-policy-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

cp "$REPO_ROOT/Sources/PressTalkCore/TranscriptRecallPolicy.swift" "$TEST_TMPDIR/TranscriptRecallPolicy.swift"
cat > "$TEST_TMPDIR/main.swift" <<'SWIFT'
import Darwin
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let policy = TranscriptRecallPolicy(chunkedWhisperFallbackMinimumCaptureSeconds: 7.5)

let mixedRecall = "Wait, let me try it again with a longer English sentence. Und dann spreche ich nochmal auf Deutsch weiter."
let germanTail = "Und dann spreche ich nochmal auf Deutsch weiter."
let translatedStatus = "Was ist der Status? Wie ist der Status?"
let recalledStatus = "What is the status? Wie ist der Status?"

expect(
    policy.shouldRejectWhisperCandidateForRecallQuality(
        whisperTranscript: germanTail,
        parakeetTranscript: mixedRecall,
        streamingTranscript: nil,
        captureDurationSeconds: 10,
        context: "tail"
    ) != nil,
    "tail-only German Whisper candidate must be rejected when recall preserves the English prefix"
)

expect(
    policy.shouldRejectWhisperCandidateForRecallQuality(
        whisperTranscript: translatedStatus,
        parakeetTranscript: recalledStatus,
        streamingTranscript: nil,
        captureDurationSeconds: 4,
        context: "translated"
    ) != nil,
    "translated Whisper candidate must be rejected when recall preserves the English prefix"
)

expect(
    policy.shouldRejectWhisperCandidateForRecallQuality(
        whisperTranscript: mixedRecall,
        parakeetTranscript: mixedRecall,
        streamingTranscript: nil,
        captureDurationSeconds: 10,
        context: "same"
    ) == nil,
    "candidate with the recalled prefix must not be rejected"
)

let longRecall = "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty one twenty two twenty three twenty four twenty five"
let shortWhisper = "fifteen sixteen seventeen"
expect(
    policy.shouldDeferShortWhisperCandidateForRecall(
        whisperTranscript: shortWhisper,
        parakeetTranscript: longRecall,
        streamingTranscript: nil,
        captureDurationSeconds: 12.5,
        context: "short"
    ) != nil,
    "much shorter Whisper candidate must defer to recall"
)

expect(
    policy.parakeetStreamingRecallFallback(
        parakeetTranscript: "One two three four five six seven eight nine with the",
        streamingTranscript: "One two three four five six seven eight nine with the rest of sentence now",
        captureDurationSeconds: 9,
        context: "parakeet"
    )?.fallbackReason?.contains("dangling_ending_with_streaming_recall") == true,
    "dangling Parakeet prefix must request streaming recall fallback"
)

let repetitive = "alpha alpha alpha beta beta beta gamma delta epsilon zeta theta iota kappa lambda mu nu omicron pi rho sigma tau upsilon phi chi"
expect(policy.hasContentStemRepetition(repetitive), "repetitive hallucinated fallback must be detected")

let merged = policy.mergeTranscriptSegments([
    "First complete sentence.",
    "First complete sentence.",
    "Second complete sentence.",
])
expect(merged == "First complete sentence. Second complete sentence.", "chunk merge must drop duplicate segments")
SWIFT

swiftc "$TEST_TMPDIR/TranscriptRecallPolicy.swift" "$TEST_TMPDIR/main.swift" -o "$TEST_TMPDIR/transcript-recall-policy-test"
"$TEST_TMPDIR/transcript-recall-policy-test"

echo "PASS transcript_recall_policy"
