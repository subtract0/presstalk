#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/presstalk_accessibility_handoff.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-accessibility-handoff-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

fixture_home="$TEST_TMPDIR/home"
fixture_bin="$TEST_TMPDIR/bin"
fixture_app="$fixture_home/Applications/PressTalk.app"
fixture_resources="$fixture_app/Contents/Resources"
fixture_status_dir="$fixture_home/Library/Application Support/JarvisTap"
fixture_status="$fixture_status_dir/runtime-status.json"
fixture_command="$fixture_home/Desktop/Grant PressTalk Accessibility.command"
fixture_tcc_system="$TEST_TMPDIR/system.TCC.db"
fixture_tcc_user="$TEST_TMPDIR/user.TCC.db"

mkdir -p "$fixture_bin" "$fixture_resources" "$fixture_status_dir" "$(dirname "$fixture_command")"
touch "$fixture_tcc_system" "$fixture_tcc_user"

cat >"$fixture_bin/sqlite3" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"kTCCServiceAccessibility"* ]]; then
  printf '%s\n' "${PRESSTALK_TEST_TCC_AUTH_VALUE:-}"
fi
SH
chmod +x "$fixture_bin/sqlite3"

cat >"$fixture_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.am.presstalk</string>
</dict>
</plist>
PLIST

cat >"$fixture_status" <<'JSON'
{
  "runtime": {
    "activeFieldInsertionReady": false,
    "activeFieldInsertionStatus": "blocked_recognized_disabled",
    "triggerKey": "option_space"
  },
  "permissions": {
    "accessibilityStatus": "ax_false_input_method_recognized_disabled",
    "inputMethodFallbackStatus": "recognized_disabled",
    "inputMonitoringEffective": true,
    "microphoneAuthorizationStatus": "authorized"
  },
  "status": {
    "adHocSigned": false,
    "codeSignatureAuthority": "PressTalk Local Development Code Signing"
  }
}
JSON

output_file="$TEST_TMPDIR/write-command.txt"
PATH="$fixture_bin:$PATH" \
  HOME="$fixture_home" \
  PRESSTALK_APP_BUNDLE="$fixture_app" \
  PRESSTALK_STATUS_JSON="$fixture_status" \
  PRESSTALK_ACCESSIBILITY_DESKTOP_COMMAND_PATH="$fixture_command" \
  PRESSTALK_SYSTEM_TCC_DB="$fixture_tcc_system" \
  PRESSTALK_USER_TCC_DB="$fixture_tcc_user" \
  PRESSTALK_TEST_TCC_AUTH_VALUE=0 \
  "$HELPER" --write-desktop-command >"$output_file"

test -x "$fixture_command"
grep -Fq "AccessibilityTCC: listed_disabled" "$output_file"
grep -Fq "turn on the existing PressTalk entry" "$output_file"
grep -Fq "If PressTalk.app is already listed but off, turn on that existing entry." "$fixture_command"
grep -Fq "Do not change Microphone, Input Monitoring, or signing settings here." "$fixture_command"
grep -Fq -- "--prompt" "$fixture_command"
grep -Fq -- "--probe" "$fixture_command"

echo "PASS accessibility_handoff"
