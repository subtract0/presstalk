#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/presstalk_repair_local_signing.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-repair-preflight-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

home_dir="$TEST_TMPDIR/home"
app_bundle="$home_dir/Applications/PressTalk.app"
resources_dir="$app_bundle/Contents/Resources"
status_dir="$home_dir/Library/Application Support/JarvisTap"
mkdir -p "$resources_dir" "$status_dir"

cat >"$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.am.presstalk</string>
</dict>
</plist>
PLIST

cat >"$resources_dir/presstalk-bootstrap.sh" <<'SH'
#!/usr/bin/env bash
echo "bootstrap should not run during preflight" >&2
exit 99
SH
chmod +x "$resources_dir/presstalk-bootstrap.sh"

cat >"$resources_dir/create-presstalk-local-codesign-identity.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${PRESSTALK_LOCAL_CODESIGN_EXISTING_ONLY:-0}" != "1" ]]; then
  echo "identity creation should not run during preflight" >&2
  exit 98
fi
case "${PRESSTALK_TEST_EXISTING_IDENTITY:-missing}" in
  ready)
    echo "PressTalk local code-signing identity is ready."
    echo "Hash: TESTHASH"
    ;;
  untrusted)
    echo "Existing PressTalk local code-signing identity is present but not trusted for code signing." >&2
    echo "Hash: UNTRUSTEDHASH" >&2
    echo "Keychain: /tmp/presstalk-test.keychain-db" >&2
    exit 1
    ;;
  *)
    echo "No existing valid PressTalk local code-signing identity is available." >&2
    exit 1
    ;;
esac
SH
chmod +x "$resources_dir/create-presstalk-local-codesign-identity.sh"

cat >"$status_dir/runtime-status.json" <<'JSON'
{
  "runtime": {
    "activeFieldInsertionStatus": "needs_signing_repair",
    "inputListener": "hid:listen_only"
  },
  "permissions": {
    "inputMethodFallbackStatus": "recognized_disabled",
    "microphoneAuthorizationStatus": "authorized",
    "inputMonitoringEffective": true
  },
  "status": {
    "adHocSigned": true,
    "codeSignatureAuthority": "unknown",
    "speechModel": "Ready"
  }
}
JSON

missing_output="$TEST_TMPDIR/missing.txt"
SSH_CONNECTION="test" HOME="$home_dir" PRESSTALK_APP_BUNDLE="$app_bundle" "$HELPER" --preflight >"$missing_output"
grep -Fq "RepairNeeded: true" "$missing_output"
grep -Fq "RepairAllowedHere: false" "$missing_output"
grep -Fq "WouldRunRepair: false" "$missing_output"
grep -Fq "SigningTrustPromptNeeded: true" "$missing_output"
grep -Fq "ExistingSigningIdentity: missing" "$missing_output"

ready_output="$TEST_TMPDIR/ready.txt"
HOME="$home_dir" PRESSTALK_APP_BUNDLE="$app_bundle" PRESSTALK_TEST_EXISTING_IDENTITY=ready "$HELPER" --preflight >"$ready_output"
grep -Fq "RepairNeeded: true" "$ready_output"
grep -Fq "RepairAllowedHere: true" "$ready_output"
grep -Fq "WouldRunRepair: true" "$ready_output"
grep -Fq "SigningTrustPromptNeeded: false" "$ready_output"
grep -Fq "ExistingSigningIdentity: ready" "$ready_output"
grep -Fq "ExistingSigningIdentityDetail: TESTHASH" "$ready_output"

cat >"$status_dir/runtime-status.json" <<'JSON'
{
  "runtime": {
    "activeFieldInsertionStatus": "blocked_recognized_disabled",
    "inputListener": "hid:listen_only"
  },
  "permissions": {
    "inputMethodFallbackStatus": "recognized_disabled",
    "microphoneAuthorizationStatus": "authorized",
    "inputMonitoringEffective": true
  },
  "status": {
    "adHocSigned": false,
    "codeSignatureAuthority": "PressTalk Local Development Code Signing",
    "speechModel": "Ready"
  }
}
JSON

local_signing_output="$TEST_TMPDIR/local-signing.txt"
SSH_CONNECTION="test" HOME="$home_dir" PRESSTALK_APP_BUNDLE="$app_bundle" "$HELPER" --preflight >"$local_signing_output"
grep -Fq "RepairNeeded: true" "$local_signing_output"
grep -Fq "RepairAllowedHere: false" "$local_signing_output"
grep -Fq "SigningTrustPromptNeeded: true" "$local_signing_output"
grep -Fq "CodeSignatureAuthority: PressTalk Local Development Code Signing" "$local_signing_output"

untrusted_output="$TEST_TMPDIR/untrusted.txt"
SSH_CONNECTION="test" HOME="$home_dir" PRESSTALK_APP_BUNDLE="$app_bundle" PRESSTALK_TEST_EXISTING_IDENTITY=untrusted "$HELPER" --preflight >"$untrusted_output"
grep -Fq "RepairNeeded: true" "$untrusted_output"
grep -Fq "RepairAllowedHere: false" "$untrusted_output"
grep -Fq "SigningTrustPromptNeeded: true" "$untrusted_output"
grep -Fq "ExistingSigningIdentity: untrusted" "$untrusted_output"
grep -Fq "ExistingSigningIdentityDetail: UNTRUSTEDHASH" "$untrusted_output"

rm -f "$status_dir/runtime-status.json"
default_trigger_output="$TEST_TMPDIR/default-trigger.txt"
HOME="$home_dir" PRESSTALK_APP_BUNDLE="$app_bundle" PRESSTALK_TEST_EXISTING_IDENTITY=ready "$HELPER" --preflight >"$default_trigger_output"
grep -Fq "Trigger: option_space" "$default_trigger_output"
grep -Fq "RepairNeeded: false" "$default_trigger_output"

desktop_command="$TEST_TMPDIR/Repair PressTalk Signing.command"
desktop_output="$TEST_TMPDIR/desktop-command.txt"
HOME="$home_dir" PRESSTALK_APP_BUNDLE="$app_bundle" PRESSTALK_REPAIR_DESKTOP_COMMAND_PATH="$desktop_command" "$HELPER" --write-desktop-command >"$desktop_output"
test -x "$desktop_command"
grep -Fq "DesktopCommand: $desktop_command" "$desktop_output"
grep -Fq "did not create or trust a certificate" "$desktop_output"
grep -Fq -- "--app-bundle '$app_bundle'" "$desktop_command"
grep -Fq -- "--trigger-key 'option_space'" "$desktop_command"
grep -Fq -- "--probe" "$desktop_command"
grep -Fq "Press Return to close this window." "$desktop_command"

echo "PASS signing_repair_preflight"
