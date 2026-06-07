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

echo "PASS machine_readiness_json"
