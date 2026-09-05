#!/usr/bin/env bash
# Drives the complete dictation journey without a human holding a key:
# trigger down, fixture audio in place of the microphone, trigger up,
# recognition, cleanup, and (optionally) insertion. Reports every run, including
# the ones that produced nothing -- a success-only percentile hides exactly the
# reliability problem you are trying to find.
#
# The installed app is stopped for the duration and restarted afterwards,
# because PressTalk holds a singleton lock.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FIXTURE=""
RUNS=5
HOLD_SECONDS=0.4
SETTLE_SECONDS=6
APP_BUNDLE=""
LABEL="fixture-replay"
ALLOW_INSERT=0
OUT_DIR=""
KEEP_APP_STOPPED=0

usage() {
  cat <<'USAGE'
Usage: presstalk_e2e_harness.sh --fixture <audio> [options]

Options:
  --fixture <path>       Audio file replayed in place of the microphone (required)
  --app <PressTalk.app>  Bundle to exercise (default: ~/Applications/PressTalk.app)
  --runs <n>             Dictation cycles to perform (default: 5)
  --hold <seconds>       Simulated key hold (default: 0.4)
  --settle <seconds>     Wait for a result after release (default: 6)
  --label <name>         Written into the report; use it to separate cold from warm
  --allow-insert         Actually paste. Off by default: a harness that types into
                         the focused window damages real work.
  --out <dir>            Where to write results (default: a temp directory)
  --keep-app-stopped     Do not restart the launchd job afterwards
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fixture) FIXTURE="${2:-}"; shift 2 ;;
    --app) APP_BUNDLE="${2:-}"; shift 2 ;;
    --runs) RUNS="${2:-}"; shift 2 ;;
    --hold) HOLD_SECONDS="${2:-}"; shift 2 ;;
    --settle) SETTLE_SECONDS="${2:-}"; shift 2 ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --allow-insert) ALLOW_INSERT=1; shift ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --keep-app-stopped) KEEP_APP_STOPPED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$FIXTURE" ]] || { echo "Missing --fixture" >&2; usage >&2; exit 2; }
[[ -f "$FIXTURE" ]] || { echo "No such fixture: $FIXTURE" >&2; exit 2; }
APP_BUNDLE="${APP_BUNDLE:-$HOME/Applications/PressTalk.app}"
[[ -d "$APP_BUNDLE" ]] || { echo "No such app bundle: $APP_BUNDLE" >&2; exit 2; }
OUT_DIR="${OUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/presstalk-e2e.XXXXXX")}"
mkdir -p "$OUT_DIR"

BINARY="$APP_BUNDLE/Contents/MacOS/jarvistap"
RESULTS="$OUT_DIR/results.jsonl"
TRACE="$OUT_DIR/trace.log"
LAUNCHD_LABEL="com.am.presstalk"
: >"$RESULTS"
: >"$TRACE"

harness_pid=""
restore_installed_app() {
  if [[ -n "$harness_pid" ]] && kill -0 "$harness_pid" 2>/dev/null; then
    kill "$harness_pid" 2>/dev/null || true
    wait "$harness_pid" 2>/dev/null || true
  fi
  if [[ "$KEEP_APP_STOPPED" == "0" ]]; then
    launchctl kickstart "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
  fi
}
trap restore_installed_app EXIT

echo "Stopping the installed PressTalk so the harness can take the singleton lock..."
launchctl kill SIGTERM "gui/$(id -u)/$LAUNCHD_LABEL" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  pgrep -f "$APP_BUNDLE/Contents/MacOS/jarvistap" >/dev/null 2>&1 || break
  perl -e 'select(undef,undef,undef,0.25)'
done
pkill -f "$APP_BUNDLE/Contents/MacOS/jarvistap" 2>/dev/null || true
perl -e 'select(undef,undef,undef,0.5)'

echo "Launching the harness build..."
PRESSTALK_TEST_HARNESS=1 \
PRESSTALK_FIXTURE_AUDIO="$FIXTURE" \
PRESSTALK_HARNESS_RESULTS="$RESULTS" \
PRESSTALK_HARNESS_ALLOW_INSERT="$ALLOW_INSERT" \
PRESSTALK_OPEN_PERMISSION_PANES=0 \
PRESSTALK_TRACE_LOG="$TRACE" \
  "$BINARY" >"$OUT_DIR/stdout.log" 2>"$OUT_DIR/stderr.log" &
harness_pid=$!

echo -n "Waiting for the speech model"
ready=0
for _ in $(seq 1 240); do
  if grep -q "Parakeet v3 ANE ready\|WhisperKit ready" "$OUT_DIR/stdout.log" 2>/dev/null; then
    ready=1
    break
  fi
  if ! kill -0 "$harness_pid" 2>/dev/null; then
    echo
    echo "The harness build exited during startup:" >&2
    tail -20 "$OUT_DIR/stderr.log" >&2
    exit 1
  fi
  echo -n "."
  perl -e 'select(undef,undef,undef,0.5)'
done
echo
[[ "$ready" == "1" ]] || { echo "Model never reported ready" >&2; tail -20 "$TRACE" >&2; exit 1; }

startup_seconds="$(grep -o 'Audio capture engine ready seconds=[0-9.]*' "$TRACE" | head -1 | cut -d= -f2 || true)"
echo "Capture engine ready in ${startup_seconds:-unknown}s"
grep -o 'Whisper quality fallback NOT loaded reason=[a-z_]*' "$TRACE" | head -1 || true

for run in $(seq 1 "$RUNS"); do
  before="$(wc -l <"$RESULTS" | tr -d ' ')"
  echo -n "run $run/$RUNS "
  /usr/bin/notifyutil -p com.am.jarvistap.trigger.press >/dev/null
  perl -e "select(undef,undef,undef,$HOLD_SECONDS)"
  /usr/bin/notifyutil -p com.am.jarvistap.trigger.release >/dev/null

  produced=0
  for _ in $(seq 1 "$((SETTLE_SECONDS * 4))"); do
    after="$(wc -l <"$RESULTS" | tr -d ' ')"
    if [[ "$after" -gt "$before" ]]; then produced=1; break; fi
    perl -e 'select(undef,undef,undef,0.25)'
  done
  if [[ "$produced" == "1" ]]; then
    echo "-> transcript"
  else
    # Recorded, not skipped. Empty runs are the interesting ones.
    echo '{"transcript": "", "outcome": "no_result"}' >>"$RESULTS"
    echo "-> NO RESULT"
  fi
  perl -e 'select(undef,undef,undef,0.5)'
done

kill "$harness_pid" 2>/dev/null || true
wait "$harness_pid" 2>/dev/null || true
harness_pid=""

python3 "$ROOT/scripts/presstalk_e2e_report.py" \
  --results "$RESULTS" --trace "$TRACE" --label "$LABEL" --fixture "$FIXTURE" \
  --out "$OUT_DIR/report.json"

echo
echo "Artifacts in $OUT_DIR"
