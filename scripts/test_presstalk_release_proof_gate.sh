#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/presstalk_release_proof_gate.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-proof-gate-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

pass_matrix="$TEST_TMPDIR/pass.json"
blocked_matrix="$TEST_TMPDIR/blocked.json"

cat >"$pass_matrix" <<'JSON'
{
  "schemaVersion": 1,
  "targets": [
    {
      "target": "local",
      "status": "ready_reported",
      "reachable": true,
      "summary": {
        "machineHost": "studio1",
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": true,
        "nextAction": "Ready for physical Fn/Option dictation smoke with active-field insertion proof."
      }
    },
    {
      "target": "mbp1-tb",
      "status": "ready_reported",
      "reachable": true,
      "summary": {
        "machineHost": "mbp1",
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": true,
        "nextAction": "Ready for physical Fn/Option dictation smoke with active-field insertion proof."
      }
    }
  ]
}
JSON

cat >"$blocked_matrix" <<'JSON'
{
  "schemaVersion": 1,
  "targets": [
    {
      "target": "local",
      "status": "ready_reported",
      "reachable": true,
      "summary": {
        "machineHost": "studio1",
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": true,
        "nextAction": "Ready for physical Fn/Option dictation smoke with active-field insertion proof."
      }
    },
    {
      "target": "mbp1-tb",
      "status": "ready_reported",
      "reachable": true,
      "summary": {
        "machineHost": "mbp1",
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": false,
        "nextAction": "Run logged-in desktop Repair Signing; do not reopen privacy panes for this state."
      }
    }
  ]
}
JSON

pass_output="$TEST_TMPDIR/pass.txt"
"$GATE" --matrix "$pass_matrix" --require studio1 --require mbp1 >"$pass_output"
grep -Fq "Result: proven" "$pass_output"
grep -Fq "PASS mbp1" "$pass_output"

blocked_output="$TEST_TMPDIR/blocked.txt"
if "$GATE" --matrix "$blocked_matrix" --require local --require mbp1-tb >"$blocked_output"; then
  echo "FAIL: blocked matrix unexpectedly passed"
  cat "$blocked_output"
  exit 1
fi
grep -Fq "activeFieldSmokeReady=false" "$blocked_output"
grep -Fq "Run logged-in desktop Repair Signing" "$blocked_output"
grep -Fq "Result: not proven" "$blocked_output"

missing_output="$TEST_TMPDIR/missing.txt"
if "$GATE" --matrix "$pass_matrix" --require s1 >"$missing_output"; then
  echo "FAIL: missing required target unexpectedly passed"
  cat "$missing_output"
  exit 1
fi
grep -Fq "FAIL s1: missing from matrix" "$missing_output"

echo "PASS release_proof_gate"
