#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$SCRIPT_DIR/presstalk-bootstrap.sh"
PROBE="$SCRIPT_DIR/presstalk-production-insertion-probe.swift"
STATUS_JSON="$HOME/Library/Application Support/JarvisTap/runtime-status.json"

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

trigger_key="${PRESSTALK_TRIGGER_KEY:-fn}"
if [[ -f "$STATUS_JSON" ]]; then
  detected_trigger="$(plutil -extract runtime.triggerKey raw -o - "$STATUS_JSON" 2>/dev/null || true)"
  if [[ -n "$detected_trigger" ]]; then
    trigger_key="$detected_trigger"
  fi
fi

restore_normal() {
  PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE=0 \
  PRESSTALK_OPEN_PERMISSION_PANES=0 \
  PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
  PRESSTALK_TRIGGER_KEY="$trigger_key" \
    /bin/bash "$BOOTSTRAP" >/dev/null 2>&1 || true
}

trap restore_normal EXIT

PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE=1 \
PRESSTALK_OPEN_PERMISSION_PANES=0 \
PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
PRESSTALK_TRIGGER_KEY="$trigger_key" \
  /bin/bash "$BOOTSTRAP" >/dev/null

sleep "${PRESSTALK_PRODUCTION_INSERTION_PROBE_STARTUP_DELAY_SECONDS:-3}"

swift "$PROBE" "$@"
