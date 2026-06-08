#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$SCRIPT_DIR/presstalk-bootstrap.sh"
PROBE="$SCRIPT_DIR/presstalk-production-insertion-probe.swift"
STATUS_JSON="$HOME/Library/Application Support/JarvisTap/runtime-status.json"
TRACE_LOG="${PRESSTALK_TRACE_LOG:-$HOME/Library/Logs/jarvistap_trace.log}"

if [[ ! -x "$BOOTSTRAP" && -x "$SCRIPT_DIR/presstalk_bootstrap.sh" ]]; then
  BOOTSTRAP="$SCRIPT_DIR/presstalk_bootstrap.sh"
fi

if [[ "$BOOTSTRAP" == "$SCRIPT_DIR/presstalk_bootstrap.sh" &&
      -x "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh" ]]; then
  BOOTSTRAP="$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-bootstrap.sh"
fi

if [[ ! -f "$PROBE" && -f "$SCRIPT_DIR/presstalk_production_insertion_probe.swift" ]]; then
  PROBE="$SCRIPT_DIR/presstalk_production_insertion_probe.swift"
fi

if [[ ! -x "$BOOTSTRAP" ]]; then
  echo "Missing bootstrap helper: $BOOTSTRAP" >&2
  exit 1
fi

if [[ ! -f "$PROBE" ]]; then
  echo "Missing production insertion probe: $PROBE" >&2
  exit 1
fi

trigger_key="${PRESSTALK_TRIGGER_KEY:-option_space}"
if [[ -f "$STATUS_JSON" ]]; then
  detected_trigger="$(plutil -extract runtime.triggerKey raw -o - "$STATUS_JSON" 2>/dev/null || true)"
  if [[ -n "$detected_trigger" ]]; then
    trigger_key="$detected_trigger"
  fi
fi

trace_line_count() {
  if [[ -f "$TRACE_LOG" ]]; then
    wc -l <"$TRACE_LOG" | tr -d '[:space:]'
  else
    printf '0'
  fi
}

wait_for_probe_notification() {
  local start_line="$1"
  local timeout_seconds="${PRESSTALK_PRODUCTION_INSERTION_PROBE_READY_TIMEOUT_SECONDS:-15}"
  local waited=0
  while (( waited < timeout_seconds )); do
    if [[ -f "$TRACE_LOG" ]] &&
       awk -v start="$start_line" '
         NR > start && /Production insertion probe notification installed/ { found=1; exit }
         END { exit(found ? 0 : 1) }
       ' "$TRACE_LOG"; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

start_line_count="$(trace_line_count)"

PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE=0 \
PRESSTALK_OPEN_PERMISSION_PANES=0 \
PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
PRESSTALK_TRIGGER_KEY="$trigger_key" \
  /bin/bash "$BOOTSTRAP" >/dev/null

if ! wait_for_probe_notification "$start_line_count"; then
  echo "Timed out waiting for PressTalk to install production insertion probe notification." >&2
  echo "Trace: $TRACE_LOG" >&2
  exit 1
fi

sleep "${PRESSTALK_PRODUCTION_INSERTION_PROBE_STARTUP_DELAY_SECONDS:-0.5}"

swift "$PROBE" "$@"
