#!/usr/bin/env bash
# Source-level invariants that runtime tests cannot see.
#
# This is a source guard rather than a runtime test because the failure is
# invisible at runtime: the app works perfectly while quietly accumulating every
# sentence the user has ever spoken in ~/Library/Logs. It went unnoticed for
# months and 1,302 transcripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES="$ROOT/Sources/JarvisTap"
failures=0

report() {
  echo "FAIL $1"
  shift
  printf '     %s\n' "$@"
  failures=$((failures + 1))
}

# Interpolations of variables that hold recognised text. Any of these reaching a
# log or stdout without TranscriptRedaction is a leak.
TRANSCRIPT_VARIABLES=(
  "transcript"
  "cleaned"
  "cleanedToLog"
  "rendered"
  "parakeetTranscript"
  "whisperTranscript"
)

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  rest="${hit#*:}"
  line_number="${rest%%:*}"
  line_text="${rest#*:}"

  printf '%s' "$line_text" | grep -q 'TranscriptRedaction' && continue
  # Counts, durations, and revisions are not the words themselves.
  printf '%s' "$line_text" | grep -qE '\.count|\.isEmpty|samples=|revision=|seconds=|error=' && continue

  report "${file#$ROOT/}:${line_number}" \
    "logs recognised text without TranscriptRedaction.loggable" \
    "${line_text#"${line_text%%[![:space:]]*}"}"
done < <(
  for variable in "${TRANSCRIPT_VARIABLES[@]}"; do
    grep -rn -E "(traceLogger\.log|print)\(.*\\\\\(${variable}\)" "$SOURCES" || true
  done
)

# The helper every recognizer candidate routes through has to redact, or the
# twelve call sites above it all leak at once.
if ! grep -A 4 'private func traceTranscriptCandidate' "$SOURCES/main.swift" \
     | grep -q 'TranscriptRedaction.loggable'; then
  report "Sources/JarvisTap/main.swift" \
    "traceTranscriptCandidate must redact; every recognizer candidate goes through it"
fi

# Redaction has to be the default, not something a flag turns on.
if ! grep -q 'isVerboseLoggingEnabled' "$ROOT/Sources/PressTalkCore/TranscriptRedaction.swift"; then
  report "Sources/PressTalkCore/TranscriptRedaction.swift" "opt-in mechanism is missing"
fi

# The grandfathering decision has to be recorded before anything writes a
# first-run default, or a brand new install looks identical to a year-old one and
# every user is grandfathered for free. Unit tests cannot see this: they hand the
# policy its evidence, while the app hands it whatever the ordering produced.
main_swift="$SOURCES/main.swift"
record_line="$(grep -n 'recordInstallGenerationIfNeeded' "$main_swift" | head -1 | cut -d: -f1 || true)"
setup_flag_line="$(grep -n 'hasSeenSetupGuide = true' "$main_swift" | head -1 | cut -d: -f1 || true)"
if [[ -z "$record_line" ]]; then
  report "Sources/JarvisTap/main.swift" \
    "startup must call recordInstallGenerationIfNeeded before any first-run write"
elif [[ -n "$setup_flag_line" && "$record_line" -gt "$setup_flag_line" ]]; then
  report "Sources/JarvisTap/main.swift:${record_line}" \
    "recordInstallGenerationIfNeeded runs after hasSeenSetupGuide is set (line ${setup_flag_line})" \
    "every new install would be classified as predating paid licensing"
fi

# An expired trial must be refused before the microphone opens. If the guard
# ever drifts below `isRecording = true`, a blocked dictation still records
# audio and still runs recognition -- the user is refused after the app has
# already listened to them, which is the opposite of what this product sells.
# Ordering is invisible to a unit test, which calls the check directly.
# Matches only executable lines. Grepping for the bare string passed when the
# guard was commented out -- verified here on 2026-09-06 by commenting it out
# and watching this script report "All source invariants hold". A check that
# accepts a disabled guard is worse than no check, because it certifies it.
live_line() { # file, pattern -> first line number where the pattern is code
  # Blanks everything from // to end of line before matching, rather than
  # skipping lines that begin with //. Two versions of this check have now been
  # defeated by a disabled guard: first `// if licenseStore.shouldBlockDictation {`,
  # then `let failure: String? = nil // Self.audioInputPreflightFailure()`, where
  # the call survives in a trailing comment on a line that starts with code.
  # sed emits every line, so grep -n still reports true line numbers.
  #
  # sed rather than awk: the awk form needs nested single quotes, and the
  # version written here first lost sub()'s empty second argument in transit and
  # silently matched everything it was supposed to filter.
  #
  # This also blanks // inside a string literal such as a URL. No invariant
  # matches inside one; if one ever does it reads as absent, which is the safe
  # direction for a check that guards a crash.
  sed 's|//.*||' "$1" | grep -n "$2" | head -1 | cut -d: -f1 || true
}
block_line="$(live_line "$main_swift" 'licenseStore\.shouldBlockDictation')"
recording_line="$(live_line "$main_swift" 'isRecording = true')"
if [[ -z "$block_line" ]]; then
  report "Sources/JarvisTap/main.swift" \
    "the trigger handler must consult licenseStore.shouldBlockDictation" \
    "without it the trial never ends and a licence buys nothing"
elif [[ -n "$recording_line" && "$block_line" -gt "$recording_line" ]]; then
  report "Sources/JarvisTap/main.swift:${block_line}" \
    "the trial check runs after isRecording is set (line ${recording_line})" \
    "a refused dictation would still have opened the microphone"
fi

# The refusal must never be reachable without somewhere to buy a licence.
if [[ -z "$(live_line "$SOURCES/ProductUI.swift" 'PressTalkOffer\.checkoutIsLive')" ]]; then
  report "Sources/JarvisTap/ProductUI.swift" \
    "shouldBlockDictation must require checkoutIsLive" \
    "otherwise an expired trial locks someone out with no way to pay"
fi

# The tap-safety preflight may be cached, but it must still be reachable. It
# guards installTapOnBus, which raises an Objective-C exception Swift cannot
# catch and which killed the app three times in six days. A cache that never
# misses would turn that guard off without removing a single line.
if [[ -z "$(live_line "$main_swift" 'Self\.audioInputPreflightFailure\(\)')" ]]; then
  report "Sources/JarvisTap/main.swift" \
    "the capture path must still be able to run audioInputPreflightFailure" \
    "a cache with no miss path silently disables the crash guard"
fi
if [[ -z "$(live_line "$main_swift" 'audioPreflightCache\.record')" ]]; then
  report "Sources/JarvisTap/main.swift" \
    "preflight results must be recorded, or the cache never hits" \
    "every press would pay the 52 ms the cache exists to avoid"
fi

echo
if [[ "$failures" -gt 0 ]]; then
  echo "$failures source invariant(s) violated." >&2
  exit 1
fi
echo "All source invariants hold."
