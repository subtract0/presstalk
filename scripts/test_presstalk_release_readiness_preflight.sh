#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/presstalk_release_readiness_preflight.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-release-readiness-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

test_artifact_audit="$TEST_TMPDIR/test-artifact-audit.json"
production_artifact_audit="$TEST_TMPDIR/production-artifact-audit.json"
proof_gate="$TEST_TMPDIR/proof-gate.json"
asr_mismatch_proof_gate="$TEST_TMPDIR/asr-mismatch-proof-gate.json"

cat >"$test_artifact_audit" <<'JSON'
{
  "schemaVersion": "1",
  "zipPath": "/tmp/PressTalk-0.0-test.zip",
  "zipSHA256": "abc123",
  "bundleIdentifier": "com.am.presstalk",
  "bundleIdentifierMatches": true,
  "bundleVersion": "0.0-test",
  "versionMatches": true,
  "codeSignVerifyPassed": true,
  "developerIDApplication": false,
  "hardenedRuntime": false,
  "distributionReady": false,
  "notarized": false,
  "passed": true,
  "failureCount": 0,
  "failures": []
}
JSON

cat >"$production_artifact_audit" <<'JSON'
{
  "schemaVersion": "1",
  "zipPath": "/tmp/PressTalk-1.0.zip",
  "zipSHA256": "def456",
  "bundleIdentifier": "com.am.presstalk",
  "bundleIdentifierMatches": true,
  "bundleVersion": "1.0",
  "versionMatches": true,
  "codeSignVerifyPassed": true,
  "developerIDApplication": true,
  "hardenedRuntime": true,
  "distributionReady": true,
  "notarized": true,
  "passed": true,
  "failureCount": 0,
  "failures": []
}
JSON

cat >"$proof_gate" <<'JSON'
{
  "schemaVersion": "1",
  "matrix": "/tmp/matrix.json",
  "proven": true,
  "failureCount": 0,
  "requiredTargets": ["local", "mbp1"],
  "targets": [
    {
      "required": "local",
      "target": "local",
      "machineHost": "studio1",
      "asrBackend": "parakeet-v3-ane",
      "asrMode": "parakeet_v3_ane_final_pass",
      "realtimePartialTranscriptionEnabled": false,
      "status": "ready_reported",
      "reachable": true,
      "physicalSTTSmokeReady": true,
      "activeFieldSmokeReady": true,
      "passed": true,
      "failures": []
    },
    {
      "required": "mbp1",
      "target": "mbp1-tb",
      "machineHost": "mbp1",
      "asrBackend": "parakeet-v3-ane",
      "asrMode": "parakeet_v3_ane_final_pass",
      "realtimePartialTranscriptionEnabled": false,
      "status": "ready_reported",
      "reachable": true,
      "physicalSTTSmokeReady": true,
      "activeFieldSmokeReady": true,
      "passed": true,
      "failures": []
    }
  ]
}
JSON

cat >"$asr_mismatch_proof_gate" <<'JSON'
{
  "schemaVersion": "1",
  "matrix": "/tmp/matrix.json",
  "proven": true,
  "failureCount": 0,
  "requiredTargets": ["local"],
  "targets": [
    {
      "required": "local",
      "target": "local",
      "machineHost": "studio1",
      "asrBackend": "parakeet-eou-320",
      "asrMode": "parakeet_eou_320_true_streaming",
      "realtimePartialTranscriptionEnabled": true,
      "status": "ready_reported",
      "reachable": true,
      "physicalSTTSmokeReady": true,
      "activeFieldSmokeReady": true,
      "passed": true,
      "failures": []
    }
  ]
}
JSON

test_pass_output="$TEST_TMPDIR/test-pass.txt"
test_pass_json="$TEST_TMPDIR/test-pass.json"
"$PREFLIGHT" \
  --artifact-audit "$test_artifact_audit" \
  --proof-gate "$proof_gate" \
  --json-output "$test_pass_json" >"$test_pass_output"
grep -Fq "TestArtifactReady: true" "$test_pass_output"
grep -Fq "ProductionReady: false" "$test_pass_output"
grep -Fq "Result: pass" "$test_pass_output"
if [[ "$(plutil -extract testArtifactReady raw -o - "$test_pass_json")" != "true" ||
      "$(plutil -extract productionReady raw -o - "$test_pass_json")" != "false" ]]; then
  echo "FAIL: test artifact JSON readiness mismatch"
  plutil -p "$test_pass_json"
  exit 1
fi

production_required_output="$TEST_TMPDIR/production-required.txt"
production_required_json="$TEST_TMPDIR/production-required.json"
if "$PREFLIGHT" \
  --artifact-audit "$test_artifact_audit" \
  --proof-gate "$proof_gate" \
  --require-production \
  --json-output "$production_required_json" >"$production_required_output"; then
  echo "FAIL: production-required preflight unexpectedly passed for test artifact"
  cat "$production_required_output"
  exit 1
fi
grep -Fq "production_distribution_required" "$production_required_output"
if [[ "$(plutil -extract passed raw -o - "$production_required_json")" != "false" ]]; then
  echo "FAIL: production-required JSON did not fail"
  plutil -p "$production_required_json"
  exit 1
fi

production_pass_output="$TEST_TMPDIR/production-pass.txt"
production_pass_json="$TEST_TMPDIR/production-pass.json"
"$PREFLIGHT" \
  --artifact-audit "$production_artifact_audit" \
  --proof-gate "$proof_gate" \
  --require-production \
  --json-output "$production_pass_json" >"$production_pass_output"
grep -Fq "ProductionReady: true" "$production_pass_output"
grep -Fq "Result: pass" "$production_pass_output"
if [[ "$(plutil -extract productionReady raw -o - "$production_pass_json")" != "true" ||
      "$(plutil -extract passed raw -o - "$production_pass_json")" != "true" ]]; then
  echo "FAIL: production pass JSON readiness mismatch"
  plutil -p "$production_pass_json"
  exit 1
fi

asr_mismatch_output="$TEST_TMPDIR/asr-mismatch.txt"
if "$PREFLIGHT" \
  --artifact-audit "$test_artifact_audit" \
  --proof-gate "$asr_mismatch_proof_gate" >"$asr_mismatch_output"; then
  echo "FAIL: ASR mismatch preflight unexpectedly passed"
  cat "$asr_mismatch_output"
  exit 1
fi
grep -Fq "proof_target_0_asr_mode_mismatch" "$asr_mismatch_output"
grep -Fq "proof_target_0_realtime_partials_enabled" "$asr_mismatch_output"

echo "PASS release_readiness_preflight"
