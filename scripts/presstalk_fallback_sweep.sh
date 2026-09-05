#!/usr/bin/env bash
# Sweeps a corpus of audio fixtures through the real dictation pipeline in one
# app session and records, per clip, whether the Whisper quality fallback fired
# and whether it changed the text.
#
# The question this answers: the fallback costs real seconds on the paste path,
# so how often does it earn them?
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR=""
LIMIT=0
APP_BUNDLE=""
OUT_DIR=""
HOLD_SECONDS=0.3
SETTLE_SECONDS=12

usage() {
  cat <<'USAGE'
Usage: presstalk_fallback_sweep.sh --fixtures <dir> [--limit n] [--out dir] [--app bundle]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fixtures) FIXTURE_DIR="${2:-}"; shift 2 ;;
    --limit) LIMIT="${2:-}"; shift 2 ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --app) APP_BUNDLE="${2:-}"; shift 2 ;;
    --settle) SETTLE_SECONDS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$FIXTURE_DIR" ]] || { echo "Missing --fixtures directory" >&2; exit 2; }
APP_BUNDLE="${APP_BUNDLE:-$HOME/Applications/PressTalk.app}"
OUT_DIR="${OUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/presstalk-sweep.XXXXXX")}"
mkdir -p "$OUT_DIR"

BINARY="$APP_BUNDLE/Contents/MacOS/jarvistap"
POINTER="$OUT_DIR/current-fixture.txt"
RESULTS="$OUT_DIR/results.jsonl"
TRACE="$OUT_DIR/trace.log"
LAUNCHD_LABEL="com.am.presstalk"
: >"$RESULTS"
: >"$TRACE"

mapfile -t FIXTURES < <(find "$FIXTURE_DIR" -type f \( -name '*.aiff' -o -name '*.wav' -o -name '*.m4a' \) | sort)
if [[ "$LIMIT" -gt 0 && "${#FIXTURES[@]}" -gt "$LIMIT" ]]; then
  FIXTURES=("${FIXTURES[@]:0:$LIMIT}")
fi
echo "Sweeping ${#FIXTURES[@]} fixtures"

harness_pid=""
cleanup() {
  [[ -n "$harness_pid" ]] && kill "$harness_pid" 2>/dev/null || true
  launchctl kickstart "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
}
trap cleanup EXIT

launchctl kill SIGTERM "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
pkill -f "$APP_BUNDLE/Contents/MacOS/jarvistap" 2>/dev/null || true
perl -e 'select(undef,undef,undef,1.0)'

printf '%s\n' "${FIXTURES[0]}" >"$POINTER"
PRESSTALK_TEST_HARNESS=1 \
PRESSTALK_FIXTURE_AUDIO="$POINTER" \
PRESSTALK_HARNESS_RESULTS="$RESULTS" \
PRESSTALK_OPEN_PERMISSION_PANES=0 \
PRESSTALK_TRACE_LOG="$TRACE" \
  "$BINARY" >"$OUT_DIR/stdout.log" 2>"$OUT_DIR/stderr.log" &
harness_pid=$!

echo -n "Waiting for the speech model"
for _ in $(seq 1 240); do
  grep -q "Parakeet v3 ANE ready\|WhisperKit ready" "$OUT_DIR/stdout.log" 2>/dev/null && break
  echo -n "."
  perl -e 'select(undef,undef,undef,0.5)'
done
echo
# The fallback loads in the background now, so give it a moment or the first
# clips would be measured against a fallback that was not yet available.
echo -n "Waiting for the quality fallback"
for _ in $(seq 1 60); do
  grep -q "Whisper quality fallback ready\|NOT loaded" "$TRACE" 2>/dev/null && break
  echo -n "."
  perl -e 'select(undef,undef,undef,0.5)'
done
echo

index=0
for fixture in "${FIXTURES[@]}"; do
  index=$((index + 1))
  printf '%s\n' "$fixture" >"$POINTER"
  before="$(wc -l <"$RESULTS" | tr -d ' ')"
  printf '[%3d/%3d] %s ' "$index" "${#FIXTURES[@]}" "$(basename "$fixture")"
  /usr/bin/notifyutil -p com.am.jarvistap.trigger.press >/dev/null
  perl -e "select(undef,undef,undef,$HOLD_SECONDS)"
  /usr/bin/notifyutil -p com.am.jarvistap.trigger.release >/dev/null
  produced=0
  for _ in $(seq 1 "$((SETTLE_SECONDS * 4))"); do
    [[ "$(wc -l <"$RESULTS" | tr -d ' ')" -gt "$before" ]] && { produced=1; break; }
    perl -e 'select(undef,undef,undef,0.25)'
  done
  if [[ "$produced" == "1" ]]; then echo "ok"; else
    printf '{"fixture": "%s", "transcript": "", "outcome": "no_result"}\n' "$(basename "$fixture")" >>"$RESULTS"
    echo "NO RESULT"
  fi
  perl -e 'select(undef,undef,undef,0.3)'
done

kill "$harness_pid" 2>/dev/null || true
harness_pid=""
echo
echo "Results: $RESULTS"
echo "Trace:   $TRACE"
