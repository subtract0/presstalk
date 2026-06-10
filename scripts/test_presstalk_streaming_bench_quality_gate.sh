#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/presstalk_streaming_bench_quality_gate.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-streaming-bench-gate-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

pass_output="$TEST_TMPDIR/pass-bench.txt"
pass_json="$TEST_TMPDIR/pass-result.json"
cat >"$pass_output" <<'TXT'
backend=parakeet-eou-320 run=0
audio=17.20s load=0.00s processing=0.68s final=0.004s rtfx=25.21
{"audioDurationSeconds":17.2,"backend":"parakeet-eou-320","characterErrorRate":0.0314,"confidence":null,"finalizationSeconds":0.004,"inputPath":"/tmp/english.wav","loadSeconds":0,"maxProcessSliceSeconds":0.020,"notes":"True streaming Parakeet EOU 120M, balanced tier.","partialUpdates":25,"referenceText":"This is a PressTalk benchmark.","rtfx":25.21,"runIndex":0,"totalProcessingSeconds":0.682,"transcript":"This is a PressTalk benchmark.","wordErrorRate":0.0638}
TXT

"$GATE" \
  --bench-output "$pass_output" \
  --expected-backend parakeet-eou-320 \
  --json-output "$pass_json" >"$TEST_TMPDIR/pass.txt"
grep -Fq "StreamingQualityReady: true" "$TEST_TMPDIR/pass.txt"
if [[ "$(plutil -extract passed raw -o - "$pass_json")" != "true" ||
      "$(plutil -extract streamingQualityReady raw -o - "$pass_json")" != "true" ||
      "$(plutil -extract reportCount raw -o - "$pass_json")" != "1" ||
      "$(plutil -extract reportBackends.0 raw -o - "$pass_json")" != "parakeet-eou-320" ]]; then
  echo "FAIL: passing bench gate JSON mismatch"
  plutil -p "$pass_json"
  exit 1
fi

final_pass_output="$TEST_TMPDIR/final-pass-bench.txt"
cat >"$final_pass_output" <<'TXT'
{"audioDurationSeconds":17.2,"backend":"parakeet-v3-ane","characterErrorRate":0.0035,"confidence":0.99,"finalizationSeconds":0.166,"inputPath":"/tmp/english.wav","loadSeconds":0,"maxProcessSliceSeconds":null,"notes":"Parakeet v3 batch/sliding-window.","partialUpdates":0,"referenceText":"This is a PressTalk benchmark.","rtfx":103.71,"runIndex":0,"totalProcessingSeconds":0.166,"transcript":"This is a PressTalk benchmark.","wordErrorRate":0.0426}
TXT
set +e
"$GATE" --bench-output "$final_pass_output" --json-output "$TEST_TMPDIR/final-pass.json" >"$TEST_TMPDIR/final-pass.txt" 2>&1
final_pass_status=$?
set -e
if [[ "$final_pass_status" -eq 0 ]]; then
  echo "FAIL: final-pass bench unexpectedly passed streaming gate"
  cat "$TEST_TMPDIR/final-pass.txt"
  exit 1
fi
grep -Fq "report_0_partial_updates_too_low" "$TEST_TMPDIR/final-pass.txt"
grep -Fq "report_0_process_slice_too_slow_or_missing" "$TEST_TMPDIR/final-pass.txt"

bad_quality_output="$TEST_TMPDIR/bad-quality-bench.txt"
cat >"$bad_quality_output" <<'TXT'
{"audioDurationSeconds":21.2,"backend":"parakeet-eou-320","characterErrorRate":0.21,"confidence":null,"finalizationSeconds":0.004,"inputPath":"/tmp/chirp.wav","loadSeconds":0,"maxProcessSliceSeconds":0.030,"notes":"bad mixed German transcript","partialUpdates":25,"referenceText":"Chirp 3 Instant Custom Voice.","rtfx":23.0,"runIndex":0,"totalProcessingSeconds":0.897,"transcript":"unusable transcript","wordErrorRate":0.42}
TXT
set +e
"$GATE" --bench-output "$bad_quality_output" --json-output "$TEST_TMPDIR/bad-quality.json" >"$TEST_TMPDIR/bad-quality.txt" 2>&1
bad_quality_status=$?
set -e
if [[ "$bad_quality_status" -eq 0 ]]; then
  echo "FAIL: bad-quality streaming bench unexpectedly passed"
  cat "$TEST_TMPDIR/bad-quality.txt"
  exit 1
fi
grep -Fq "report_0_wer_too_high_or_missing" "$TEST_TMPDIR/bad-quality.txt"
grep -Fq "report_0_cer_too_high_or_missing" "$TEST_TMPDIR/bad-quality.txt"

missing_reference_output="$TEST_TMPDIR/missing-reference-bench.txt"
cat >"$missing_reference_output" <<'TXT'
{"audioDurationSeconds":17.2,"backend":"nemotron-560","finalizationSeconds":0.013,"inputPath":"/tmp/english.wav","loadSeconds":0,"maxProcessSliceSeconds":0.020,"notes":"True streaming Nemotron.","partialUpdates":20,"referenceText":null,"rtfx":19.76,"runIndex":0,"totalProcessingSeconds":0.871,"transcript":"This is a PressTalk benchmark.","wordErrorRate":null,"characterErrorRate":null}
TXT
set +e
"$GATE" --bench-output "$missing_reference_output" >"$TEST_TMPDIR/missing-reference.txt" 2>&1
missing_reference_status=$?
set -e
if [[ "$missing_reference_status" -eq 0 ]]; then
  echo "FAIL: missing-reference bench unexpectedly passed by default"
  cat "$TEST_TMPDIR/missing-reference.txt"
  exit 1
fi
grep -Fq "report_0_reference_missing" "$TEST_TMPDIR/missing-reference.txt"
"$GATE" --bench-output "$missing_reference_output" --allow-missing-reference >"$TEST_TMPDIR/missing-reference-allowed.txt"
grep -Fq "StreamingQualityReady: true" "$TEST_TMPDIR/missing-reference-allowed.txt"

echo "PASS streaming_bench_quality_gate"
