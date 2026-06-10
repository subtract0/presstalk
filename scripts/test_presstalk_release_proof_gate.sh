#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/presstalk_release_proof_gate.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-proof-gate-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

pass_matrix="$TEST_TMPDIR/pass.json"
blocked_matrix="$TEST_TMPDIR/blocked.json"
failed_alias_matrix="$TEST_TMPDIR/failed-alias.json"

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
        "asrBackend": "parakeet-v3-ane",
        "streamingASRBackend": "parakeet-eou-320",
        "asrMode": "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials",
        "realtimePartialTranscriptionEnabled": true,
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": true,
        "nextAction": "Ready for physical Option + Space dictation smoke with active-field insertion proof."
      }
    },
    {
      "target": "mbp1-tb",
      "status": "ready_reported",
      "reachable": true,
      "summary": {
        "machineHost": "mbp1",
        "asrBackend": "parakeet-v3-ane",
        "streamingASRBackend": "parakeet-eou-320",
        "asrMode": "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials",
        "realtimePartialTranscriptionEnabled": true,
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": true,
        "nextAction": "Ready for physical Option + Space dictation smoke with active-field insertion proof."
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
        "asrBackend": "parakeet-v3-ane",
        "streamingASRBackend": "parakeet-eou-320",
        "asrMode": "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials",
        "realtimePartialTranscriptionEnabled": true,
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": true,
        "nextAction": "Ready for physical Option + Space dictation smoke with active-field insertion proof."
      }
    },
    {
      "target": "mbp1-tb",
      "status": "ready_reported",
      "reachable": true,
      "summary": {
        "machineHost": "mbp1",
        "asrBackend": "parakeet-v3-ane",
        "streamingASRBackend": "parakeet-eou-320",
        "asrMode": "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials",
        "realtimePartialTranscriptionEnabled": true,
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": false,
        "nextAction": "Run logged-in desktop Repair Signing; do not reopen privacy panes for this state."
      }
    }
  ]
}
JSON

cat >"$failed_alias_matrix" <<'JSON'
{
  "schemaVersion": 1,
  "targets": [
    {
      "target": "local",
      "status": "ready_reported",
      "reachable": true,
      "summary": {
        "machineHost": "studio1",
        "asrBackend": "parakeet-v3-ane",
        "streamingASRBackend": "parakeet-eou-320",
        "asrMode": "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials",
        "realtimePartialTranscriptionEnabled": true,
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": true,
        "nextAction": "Ready for physical dictation smoke."
      }
    },
    {
      "target": "mbp1-tb",
      "status": "failed",
      "reachable": false,
      "error": "ssh: connect to host 10.77.77.3 port 22: Operation timed out",
      "summary": {
        "machineHost": "unknown",
        "asrBackend": "unknown",
        "streamingASRBackend": "unknown",
        "asrMode": "unknown",
        "realtimePartialTranscriptionEnabled": "unknown",
        "physicalSTTSmokeReady": "unknown",
        "activeFieldSmokeReady": "unknown",
        "nextAction": "Fix host/readiness collection error, then rerun matrix."
      }
    }
  ]
}
JSON

pass_output="$TEST_TMPDIR/pass.txt"
pass_json="$TEST_TMPDIR/pass-result.json"
"$GATE" --matrix "$pass_matrix" --require studio1 --require mbp1 --json-output "$pass_json" >"$pass_output"
grep -Fq "Result: proven" "$pass_output"
grep -Fq "PASS mbp1" "$pass_output"
grep -Fq "streamingASRBackend=parakeet-eou-320" "$pass_output"
grep -Fq "asrMode=parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials" "$pass_output"
if [[ "$(plutil -extract proven raw -o - "$pass_json")" != "true" ]]; then
  echo "FAIL: pass JSON did not report proven=true"
  plutil -p "$pass_json"
  exit 1
fi
if [[ "$(plutil -extract failureCount raw -o - "$pass_json")" != "0" ]]; then
  echo "FAIL: pass JSON did not report failureCount=0"
  plutil -p "$pass_json"
  exit 1
fi
if [[ "$(plutil -extract targets.0.streamingASRBackend raw -o - "$pass_json")" != "parakeet-eou-320" ||
      "$(plutil -extract targets.0.asrMode raw -o - "$pass_json")" != "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials" ||
      "$(plutil -extract targets.0.realtimePartialTranscriptionEnabled raw -o - "$pass_json")" != "true" ]]; then
  echo "FAIL: pass JSON did not preserve ASR mode evidence"
  plutil -p "$pass_json"
  exit 1
fi

blocked_output="$TEST_TMPDIR/blocked.txt"
blocked_json="$TEST_TMPDIR/blocked-result.json"
if "$GATE" --matrix "$blocked_matrix" --require local --require mbp1-tb --json-output "$blocked_json" >"$blocked_output"; then
  echo "FAIL: blocked matrix unexpectedly passed"
  cat "$blocked_output"
  exit 1
fi
grep -Fq "activeFieldSmokeReady=false" "$blocked_output"
grep -Fq "Run logged-in desktop Repair Signing" "$blocked_output"
grep -Fq "Result: not proven" "$blocked_output"
if [[ "$(plutil -extract proven raw -o - "$blocked_json")" != "false" ]]; then
  echo "FAIL: blocked JSON did not report proven=false"
  plutil -p "$blocked_json"
  exit 1
fi
if [[ "$(plutil -extract targets.1.failures.0 raw -o - "$blocked_json")" != "active_field_not_ready" ]]; then
  echo "FAIL: blocked JSON did not record active_field_not_ready"
  plutil -p "$blocked_json"
  exit 1
fi

failed_alias_output="$TEST_TMPDIR/failed-alias.txt"
failed_alias_json="$TEST_TMPDIR/failed-alias-result.json"
if "$GATE" --matrix "$failed_alias_matrix" --require studio1 --require mbp1 --json-output "$failed_alias_json" >"$failed_alias_output"; then
  echo "FAIL: failed alias matrix unexpectedly passed"
  cat "$failed_alias_output"
  exit 1
fi
grep -Fq "FAIL mbp1: status=failed target=mbp1-tb" "$failed_alias_output"
grep -Fq "FAIL mbp1: reachable=false target=mbp1-tb" "$failed_alias_output"
if grep -Fq "FAIL mbp1: missing from matrix" "$failed_alias_output"; then
  echo "FAIL: failed alias proof should not degrade to missing_from_matrix"
  cat "$failed_alias_output"
  exit 1
fi
if [[ "$(plutil -extract targets.1.target raw -o - "$failed_alias_json")" != "mbp1-tb" ||
      "$(plutil -extract targets.1.failures.0 raw -o - "$failed_alias_json")" != "status_not_ready_reported" ||
      "$(plutil -extract targets.1.failures.1 raw -o - "$failed_alias_json")" != "not_reachable" ]]; then
  echo "FAIL: failed alias JSON did not preserve mbp1-tb failure evidence"
  plutil -p "$failed_alias_json"
  exit 1
fi

unknown_asr_matrix="$TEST_TMPDIR/unknown-asr.json"
cat >"$unknown_asr_matrix" <<'JSON'
{
  "schemaVersion": 1,
  "targets": [
    {
      "target": "local",
      "status": "ready_reported",
      "reachable": true,
      "summary": {
        "machineHost": "studio1",
        "asrBackend": "unknown",
        "streamingASRBackend": "unknown",
        "asrMode": "unknown",
        "realtimePartialTranscriptionEnabled": "unknown",
        "physicalSTTSmokeReady": true,
        "activeFieldSmokeReady": true,
        "nextAction": "Install or restart a current PressTalk build that writes ASR mode evidence."
      }
    }
  ]
}
JSON
unknown_asr_output="$TEST_TMPDIR/unknown-asr.txt"
unknown_asr_json="$TEST_TMPDIR/unknown-asr-result.json"
if "$GATE" --matrix "$unknown_asr_matrix" --require studio1 --json-output "$unknown_asr_json" >"$unknown_asr_output"; then
  echo "FAIL: unknown ASR matrix unexpectedly passed"
  cat "$unknown_asr_output"
  exit 1
fi
grep -Fq "asrBackend=unknown" "$unknown_asr_output"
grep -Fq "streamingASRBackend=unknown" "$unknown_asr_output"
grep -Fq "asrMode=unknown" "$unknown_asr_output"
grep -Fq "realtimePartialTranscriptionEnabled=unknown" "$unknown_asr_output"
grep -Fq "asr_backend_missing" "$unknown_asr_json"
grep -Fq "streaming_asr_backend_missing" "$unknown_asr_json"
grep -Fq "asr_mode_missing" "$unknown_asr_json"
grep -Fq "realtime_partial_transcription_state_missing" "$unknown_asr_json"

missing_output="$TEST_TMPDIR/missing.txt"
if "$GATE" --matrix "$pass_matrix" --require s1 >"$missing_output"; then
  echo "FAIL: missing required target unexpectedly passed"
  cat "$missing_output"
  exit 1
fi
grep -Fq "FAIL s1: missing from matrix" "$missing_output"

echo "PASS release_proof_gate"
