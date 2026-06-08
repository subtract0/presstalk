#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/presstalk_machine_readiness.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-readiness-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

json_report="$TEST_TMPDIR/readiness.json"
json_output_report="$TEST_TMPDIR/readiness-output.json"
text_report="$TEST_TMPDIR/readiness.txt"

"$HELPER" --json >"$json_report"

extract_required() {
  local key_path="$1"
  local value
  value="$(plutil -extract "$key_path" raw -o - "$json_report" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    echo "FAIL: missing JSON key $key_path"
    exit 1
  fi
  printf '%s\n' "$value"
}

schema_version="$(extract_required schemaVersion)"
if [[ "$schema_version" != "1" ]]; then
  echo "FAIL: unexpected schemaVersion $schema_version"
  exit 1
fi

extract_required machine.architecture >/dev/null
extract_required audio.microphoneHardwareDetected >/dev/null
extract_required pressTalk.installed >/dev/null
extract_required runtime.statusAvailable >/dev/null
extract_required eligibility.installSmokeEligible >/dev/null
extract_required eligibility.physicalSTTSmokeReady >/dev/null
extract_required eligibility.activeFieldSmokeReady >/dev/null
extract_required latestProductionInsertionProbe.path >/dev/null
extract_required latestManualPhysicalTriggerSmoke.path >/dev/null
extract_required nextAction >/dev/null

"$HELPER" --json-output "$json_output_report" >"$text_report"
if [[ ! -s "$json_output_report" ]]; then
  echo "FAIL: --json-output did not write a report"
  exit 1
fi
if ! grep -Fq "ReadinessJSON: $json_output_report" "$text_report"; then
  echo "FAIL: text output did not report JSON path"
  exit 1
fi

fixture_home="$TEST_TMPDIR/home"
fixture_bin="$TEST_TMPDIR/bin"
fixture_app="$fixture_home/Applications/PressTalk.app"
fixture_resources="$fixture_app/Contents/Resources"
fixture_status_dir="$fixture_home/Library/Application Support/JarvisTap"
fixture_status="$fixture_status_dir/runtime-status.json"
fixture_diagnostics="$fixture_status_dir/Diagnostics"
fixture_handoff="$fixture_home/Desktop/Grant PressTalk Accessibility.command"
mkdir -p "$fixture_bin" "$fixture_resources" "$fixture_status_dir" "$fixture_diagnostics" "$(dirname "$fixture_handoff")"

cat >"$fixture_bin/system_profiler" <<'SH'
#!/usr/bin/env bash
cat <<'EOF'
Audio:

    Built-in Microphone:

      Input Channels: 1
EOF
SH
chmod +x "$fixture_bin/system_profiler"

cat >"$fixture_bin/codesign" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"-dv"* ]]; then
  cat >&2 <<'EOF'
Identifier=com.am.presstalk
CDHash=TESTCDHASH
Authority=PressTalk Local Development Code Signing
EOF
  exit 0
fi
exit 0
SH
chmod +x "$fixture_bin/codesign"

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
    "inputListener": "carbon:registered",
    "inputPipelineReady": true
  },
  "permissions": {
    "accessibilityStatus": "ax_false_input_method_recognized_disabled",
    "inputMethodFallbackStatus": "recognized_disabled",
    "inputMonitoringEffective": true,
    "microphoneAuthorizationStatus": "authorized"
  },
  "status": {
    "adHocSigned": false,
    "codeSignatureAuthority": "PressTalk Local Development Code Signing",
    "speechModel": "Ready",
    "triggerPath": "Option + Space ready"
  }
}
JSON

touch "$fixture_handoff"
chmod +x "$fixture_handoff"

fixture_with_command_json="$TEST_TMPDIR/fixture-with-command.json"
PATH="$fixture_bin:$PATH" \
  HOME="$fixture_home" \
  PRESSTALK_APP_BUNDLE="$fixture_app" \
  PRESSTALK_STATUS_JSON="$fixture_status" \
  PRESSTALK_DIAGNOSTICS_DIR="$fixture_diagnostics" \
  PRESSTALK_ACCESSIBILITY_DESKTOP_COMMAND_PATH="$fixture_handoff" \
  "$HELPER" --json >"$fixture_with_command_json"

with_command_next_action="$(plutil -extract nextAction raw -o - "$fixture_with_command_json")"
if [[ "$with_command_next_action" != *"double-click $fixture_handoff"* ]]; then
  echo "FAIL: recognized_disabled with desktop handoff did not point at handoff command"
  plutil -p "$fixture_with_command_json"
  exit 1
fi
if [[ "$with_command_next_action" == *"Repair Signing"* || "$with_command_next_action" == *"Microphone"* || "$with_command_next_action" == *"Input Monitoring"* ]]; then
  echo "FAIL: recognized_disabled post-repair guidance regressed to repair/permission wording"
  printf '%s\n' "$with_command_next_action"
  exit 1
fi

rm -f "$fixture_handoff"
cat >"$fixture_resources/presstalk-accessibility-handoff.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fixture_resources/presstalk-accessibility-handoff.sh"

fixture_write_command_json="$TEST_TMPDIR/fixture-write-command.json"
PATH="$fixture_bin:$PATH" \
  HOME="$fixture_home" \
  PRESSTALK_APP_BUNDLE="$fixture_app" \
  PRESSTALK_STATUS_JSON="$fixture_status" \
  PRESSTALK_DIAGNOSTICS_DIR="$fixture_diagnostics" \
  PRESSTALK_ACCESSIBILITY_DESKTOP_COMMAND_PATH="$fixture_handoff" \
  "$HELPER" --json >"$fixture_write_command_json"

write_command_next_action="$(plutil -extract nextAction raw -o - "$fixture_write_command_json")"
if [[ "$write_command_next_action" != *"presstalk-accessibility-handoff.sh\" --write-desktop-command"* ]]; then
  echo "FAIL: recognized_disabled without desktop handoff did not point at handoff writer"
  plutil -p "$fixture_write_command_json"
  exit 1
fi

echo "PASS machine_readiness_json"
