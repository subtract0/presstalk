#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/Sources/JarvisTap/main.swift"

require_contains() {
  local needle="$1"
  local message="$2"
  if ! rg -q --fixed-strings "$needle" "$SOURCE"; then
    echo "FAIL: $message"
    echo "missing: $needle"
    exit 1
  fi
}

require_contains "releaseLatchedAlternateModifierAfterInsertionIfNeeded(reason: String)" "PressTalk must expose a bounded post-insertion Option cleanup"
require_contains "guard !configuredTriggerUsesAlternateModifier else { return }" "Option cleanup must not run for Option-based triggers"
require_contains "CGEventSource.flagsState(.hidSystemState)" "Option cleanup must inspect the HID modifier state before posting key-up events"
require_contains "CGEventSource.flagsState(.combinedSessionState)" "Option cleanup must inspect the combined session modifier state before posting key-up events"
require_contains "CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption)" "Option cleanup must release both left and right Option keys"
require_contains "Released latched Option modifier after insertion" "Option cleanup must leave a trace receipt when it acts"
require_contains "releaseLatchedAlternateModifierAfterInsertionIfNeeded(reason: method)" "Successful insertion paths must invoke modifier cleanup"
require_contains "releaseLatchedAlternateModifierAfterInsertionIfNeeded(reason: \"paste_command_posted\")" "Paste-command insertion paths must invoke modifier cleanup"

echo "PASS modifier_cleanup_source"
