#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/presstalk_distribution_signing_preflight.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-distribution-signing-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

fake_bin="$TEST_TMPDIR/bin"
mkdir -p "$fake_bin"

write_fake_security() {
  local output_file="$1"
  cat >"$fake_bin/security" <<SH
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "find-identity" ]]; then
  cat "$output_file"
  exit 0
fi
echo "unexpected security args: \$*" >&2
exit 2
SH
  chmod +x "$fake_bin/security"
}

cat >"$fake_bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "fake xcrun $*"
SH
chmod +x "$fake_bin/xcrun"

missing_identities="$TEST_TMPDIR/missing-identities.txt"
cat >"$missing_identities" <<'TXT'
     0 valid identities found
TXT
write_fake_security "$missing_identities"

missing_output="$TEST_TMPDIR/missing-output.txt"
missing_json="$TEST_TMPDIR/missing.json"
set +e
PATH="$fake_bin:/usr/bin:/bin" \
PRESSTALK_SECURITY_CMD=security \
PRESSTALK_XCRUN_CMD=missing-xcrun \
  "$PREFLIGHT" --require-notarization --json-output "$missing_json" >"$missing_output" 2>&1
missing_status=$?
set -e
if [[ "$missing_status" -eq 0 ]]; then
  echo "FAIL: missing distribution signing preflight unexpectedly passed"
  cat "$missing_output"
  exit 1
fi
grep -Fq "Developer ID identity: missing" "$missing_output"
grep -Fq "Production signing ready: false" "$missing_output"
grep -Fq "developer_id_application_identity_missing" "$missing_output"
grep -Fq "xcrun_command_missing" "$missing_output"
grep -Fq "notary_credentials_missing" "$missing_output"
if [[ "$(plutil -extract productionSigningReady raw -o - "$missing_json")" != "false" ||
      "$(plutil -extract identityReady raw -o - "$missing_json")" != "false" ||
      "$(plutil -extract notaryCredentialsReady raw -o - "$missing_json")" != "false" ]]; then
  echo "FAIL: missing readiness JSON mismatch"
  plutil -p "$missing_json"
  exit 1
fi

developer_identities="$TEST_TMPDIR/developer-identities.txt"
cat >"$developer_identities" <<'TXT'
  1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 "Developer ID Application: Alex Example (TEAMID)"
  2) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Alex Example (TEAMID)"
     2 valid identities found
TXT
write_fake_security "$developer_identities"

ready_output="$TEST_TMPDIR/ready-output.txt"
ready_json="$TEST_TMPDIR/ready.json"
PATH="$fake_bin:/usr/bin:/bin" \
PRESSTALK_SECURITY_CMD=security \
PRESSTALK_XCRUN_CMD=xcrun \
PRESSTALK_NOTARYTOOL_PROFILE=presstalk-notary \
  "$PREFLIGHT" --require-notarization --json-output "$ready_json" >"$ready_output"
grep -Fq "Developer ID identity: ready" "$ready_output"
grep -Fq "Selected identity: Developer ID Application: Alex Example (TEAMID)" "$ready_output"
grep -Fq "Notarization credentials: ready (profile)" "$ready_output"
grep -Fq "Production signing ready: true" "$ready_output"
grep -Fq "PRESSTALK_DISTRIBUTION_SIGNING=1" "$ready_output"
if [[ "$(plutil -extract productionSigningReady raw -o - "$ready_json")" != "true" ||
      "$(plutil -extract selectedIdentity raw -o - "$ready_json")" != "Developer ID Application: Alex Example (TEAMID)" ||
      "$(plutil -extract notaryCredentialMode raw -o - "$ready_json")" != "profile" ]]; then
  echo "FAIL: ready JSON mismatch"
  plutil -p "$ready_json"
  exit 1
fi

requested_dev_output="$TEST_TMPDIR/requested-dev-output.txt"
requested_dev_json="$TEST_TMPDIR/requested-dev.json"
PATH="$fake_bin:/usr/bin:/bin" \
PRESSTALK_SECURITY_CMD=security \
PRESSTALK_XCRUN_CMD=xcrun \
PRESSTALK_NOTARY_APPLE_ID=redacted@example.com \
PRESSTALK_NOTARY_TEAM_ID=TEAMID \
PRESSTALK_NOTARY_PASSWORD=redacted-password \
  "$PREFLIGHT" --require-notarization --identity ABCDEF1234567890ABCDEF1234567890ABCDEF12 \
    --json-output "$requested_dev_json" >"$requested_dev_output"
grep -Fq "Notarization credentials: ready (apple_id_env)" "$requested_dev_output"
if grep -Fq "redacted-password" "$requested_dev_output"; then
  echo "FAIL: preflight printed password value"
  cat "$requested_dev_output"
  exit 1
fi
if [[ "$(plutil -extract productionSigningReady raw -o - "$requested_dev_json")" != "true" ||
      "$(plutil -extract identitySource raw -o - "$requested_dev_json")" != "requested" ||
      "$(plutil -extract notaryCredentialMode raw -o - "$requested_dev_json")" != "apple_id_env" ]]; then
  echo "FAIL: requested Developer ID JSON mismatch"
  plutil -p "$requested_dev_json"
  exit 1
fi

requested_non_dev_output="$TEST_TMPDIR/requested-non-dev-output.txt"
requested_non_dev_json="$TEST_TMPDIR/requested-non-dev.json"
set +e
PATH="$fake_bin:/usr/bin:/bin" \
PRESSTALK_SECURITY_CMD=security \
PRESSTALK_XCRUN_CMD=xcrun \
PRESSTALK_NOTARYTOOL_PROFILE=presstalk-notary \
  "$PREFLIGHT" --require-notarization --identity "Apple Development" \
    --json-output "$requested_non_dev_json" >"$requested_non_dev_output" 2>&1
requested_non_dev_status=$?
set -e
if [[ "$requested_non_dev_status" -eq 0 ]]; then
  echo "FAIL: Apple Development identity unexpectedly passed production preflight"
  cat "$requested_non_dev_output"
  exit 1
fi
grep -Fq "requested_identity_is_not_developer_id_application" "$requested_non_dev_output"
if [[ "$(plutil -extract productionSigningReady raw -o - "$requested_non_dev_json")" != "false" ||
      "$(plutil -extract notaryCredentialsReady raw -o - "$requested_non_dev_json")" != "true" ]]; then
  echo "FAIL: non-Developer ID JSON mismatch"
  plutil -p "$requested_non_dev_json"
  exit 1
fi

echo "PASS distribution_signing_preflight"
