#!/usr/bin/env bash
# Keeps Astra running as PressTalk's sales operator across many turns.
#
# Not a daemon. codex app-server needs a standalone install this machine does
# not have, and adding one is a system change nobody asked for. `codex exec
# resume` gives the thing that actually matters -- the same session, with its
# own memory of what it already tried -- and needs nothing installed.
#
# The first run seeds from the brief. Every run after resumes that session and
# says only "continue", because supplying a method to an Astra-class model is
# the mistake this whole handover exists to avoid. Its state lives in the files
# it writes: docs/launch/LOG.md and docs/launch/ASKS.md.
#
# Usage:
#   scripts/astra_sales_loop.sh            # one turn
#   scripts/astra_sales_loop.sh --watch    # a turn every 6 hours until stopped
#   scripts/astra_sales_loop.sh --reset    # abandon the session and start over
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIEF="$ROOT/docs/launch/ASTRA_OPERATOR_BRIEF.md"
STATE_DIR="$HOME/.presstalk-sales"
SESSION_FILE="$STATE_DIR/astra-session-id"
RUN_LOG_DIR="$STATE_DIR/runs"
MODEL="${ASTRA_MODEL:-gpt-6-astra}"
EFFORT="${ASTRA_EFFORT:-xhigh}"
INTERVAL="${ASTRA_INTERVAL_SECONDS:-21600}"   # 6 hours

mkdir -p "$STATE_DIR" "$RUN_LOG_DIR"

if [[ "${1:-}" == "--reset" ]]; then
  [[ -f "$SESSION_FILE" ]] && mv "$SESSION_FILE" "$SESSION_FILE.$(date +%Y%m%d-%H%M%S).bak"
  echo "Session forgotten. The next run starts fresh from the brief."
  exit 0
fi

[[ -f "$BRIEF" ]] || { echo "Brief missing: $BRIEF" >&2; exit 1; }
command -v codex >/dev/null || { echo "codex not on PATH" >&2; exit 1; }

run_once() {
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local out="$RUN_LOG_DIR/$stamp.txt"
  local last="$RUN_LOG_DIR/$stamp.last-message.md"
  cd "$ROOT" || return 1

  if [[ -s "$SESSION_FILE" ]]; then
    local sid; sid="$(cat "$SESSION_FILE")"
    echo "[$stamp] resuming $sid"
    # Deliberately almost empty. It knows the objective; it wrote the log.
    printf '%s\n' \
      "Continue. Read docs/launch/LOG.md and docs/launch/ASKS.md for where you left off, then keep working the objective." \
      | codex exec resume "$sid" -m "$MODEL" \
          -c model_reasoning_effort="$EFFORT" \
          --skip-git-repo-check -o "$last" - > "$out" 2>&1
  else
    echo "[$stamp] first run, seeding from the brief"
    codex exec -m "$MODEL" -c model_reasoning_effort="$EFFORT" \
      --skip-git-repo-check -o "$last" - < "$BRIEF" > "$out" 2>&1
    # Record the session so every later turn is the same Astra, not a new one
    # that has forgotten what it already tried.
    local sid
    # Anchored on codex's own "session id:" header line. Grepping for the first
    # UUID-shaped string in the transcript would happily capture one Astra
    # printed while working, and every later turn would resume the wrong
    # conversation -- or none.
    sid="$(sed 's/\x1b\[[0-9;]*m//g' "$out" \
           | grep -iE '^session id:' | head -1 \
           | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')"
    if [[ -n "$sid" ]]; then
      printf '%s' "$sid" > "$SESSION_FILE"
      echo "[$stamp] session $sid recorded"
    else
      echo "[$stamp] WARNING: no session id found. The next run will start" \
           "from the brief again and Astra will repeat work it has already done." >&2
    fi
  fi

  local status=$?
  echo "[$stamp] exit $status · transcript $out"
  [[ -s "$last" ]] && { echo "--- what it said ---"; tail -40 "$last"; }
  return $status
}

if [[ "${1:-}" == "--watch" ]]; then
  echo "Every $((INTERVAL/3600))h until stopped. Ctrl-C to end."
  while true; do
    run_once || echo "run failed; trying again next interval"
    sleep "$INTERVAL"
  done
else
  run_once
fi
