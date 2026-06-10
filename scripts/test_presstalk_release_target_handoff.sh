#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDOFF="$SCRIPT_DIR/presstalk_release_target_handoff.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-target-handoff-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

candidate_json="$TEST_TMPDIR/candidate-preflight.json"
proof_json="$TEST_TMPDIR/proof-gate.json"
host_json="$TEST_TMPDIR/host-discovery.json"
handoff_json="$TEST_TMPDIR/target-handoff.json"
handoff_output="$TEST_TMPDIR/target-handoff.txt"

cat >"$proof_json" <<'JSON'
{
  "schemaVersion": 1,
  "proven": false,
  "excludedTargets": [
    "studio2=no attached microphone"
  ],
  "targets": [
    {
      "required": "studio1",
      "target": "local",
      "machineHost": "studio1",
      "status": "ready_reported",
      "passed": true,
      "reachable": true,
      "streamingASRBackend": "parakeet-eou-320",
      "asrMode": "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials"
    },
    {
      "required": "mbp1",
      "target": "mbp1-tb",
      "machineHost": "unknown",
      "status": "failed",
      "passed": false,
      "reachable": false,
      "streamingASRBackend": "unknown",
      "asrMode": "unknown",
      "nextAction": "Fix host/readiness collection error, then rerun matrix."
    }
  ]
}
JSON

cat >"$host_json" <<'JSON'
{
  "schemaVersion": "1",
  "targets": [
    {
      "target": "mbp1-tb",
      "sshProbe": {
        "enabled": true,
        "success": false,
        "error": "ssh: connect to host 10.77.77.3 port 22: Operation timed out"
      }
    }
  ]
}
JSON

cat >"$candidate_json" <<JSON
{
  "schemaVersion": "1",
  "version": "0.1.6-test5",
  "passed": false,
  "failureStep": "proof_gate",
  "failureStatus": 1,
  "proofGateJSON": "$proof_json",
  "hostDiscoveryJSON": "$host_json",
  "requiredTargets": [
    "studio1",
    "mbp1"
  ]
}
JSON

set +e
"$HANDOFF" --candidate-preflight "$candidate_json" --json-output "$handoff_json" >"$handoff_output"
handoff_status=$?
set -e
if [[ "$handoff_status" -eq 0 ]]; then
  echo "FAIL: blocked target handoff unexpectedly passed"
  cat "$handoff_output"
  exit 1
fi

grep -Fq "PressTalk release target handoff" "$handoff_output"
grep -Fq "READY studio1: target=local machine=studio1 streamingASRBackend=parakeet-eou-320 asrMode=parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials" "$handoff_output"
grep -Fq "BLOCKED mbp1: target=mbp1-tb machine=unknown status=failed reachable=false" "$handoff_output"
grep -Fq "ssh error: ssh: connect to host 10.77.77.3 port 22: Operation timed out" "$handoff_output"
grep -Fq "studio2=no attached microphone" "$handoff_output"
grep -Fq "bash scripts/presstalk_release_candidate_preflight.sh 0.1.6-test5 --local --host mbp1-tb --require studio1 --require mbp1 --exclude-host studio2=no\\ attached\\ microphone" "$handoff_output"
grep -Fq "TargetHandoffJSON: $handoff_json" "$handoff_output"

if [[ "$(plutil -extract blockedTargetCount raw -o - "$handoff_json")" != "1" ||
      "$(plutil -extract readyTargetCount raw -o - "$handoff_json")" != "1" ||
      "$(plutil -extract failureStep raw -o - "$handoff_json")" != "proof_gate" ||
      "$(plutil -extract blockedTargets.0 raw -o - "$handoff_json")" != "mbp1: target=mbp1-tb status=failed reachable=false" ||
      "$(plutil -extract excludedTargets.0 raw -o - "$handoff_json")" != "studio2=no attached microphone" ]]; then
  echo "FAIL: handoff JSON mismatch"
  plutil -p "$handoff_json"
  exit 1
fi

ready_proof_json="$TEST_TMPDIR/ready-proof-gate.json"
ready_candidate_json="$TEST_TMPDIR/ready-candidate-preflight.json"
ready_output="$TEST_TMPDIR/ready-handoff.txt"
cat >"$ready_proof_json" <<'JSON'
{
  "schemaVersion": 1,
  "proven": true,
  "targets": [
    {
      "required": "studio1",
      "target": "local",
      "machineHost": "studio1",
      "status": "ready_reported",
      "passed": true,
      "reachable": true,
      "streamingASRBackend": "parakeet-eou-320",
      "asrMode": "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials"
    }
  ]
}
JSON
cat >"$ready_candidate_json" <<JSON
{
  "schemaVersion": "1",
  "version": "0.1.6-test5",
  "passed": true,
  "proofGateJSON": "$ready_proof_json",
  "requiredTargets": [
    "studio1"
  ]
}
JSON

"$HANDOFF" --candidate-preflight "$ready_candidate_json" >"$ready_output"
grep -Fq "Proof proven: true" "$ready_output"
grep -Fq "READY studio1: target=local machine=studio1 streamingASRBackend=parakeet-eou-320 asrMode=parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials" "$ready_output"

echo "PASS release_target_handoff"
