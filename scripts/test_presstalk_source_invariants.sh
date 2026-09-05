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

echo
if [[ "$failures" -gt 0 ]]; then
  echo "$failures place(s) can write dictated text to a log." >&2
  exit 1
fi
echo "All source invariants hold."
