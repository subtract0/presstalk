#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/presstalk_hybrid_streaming_quality_gate.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-hybrid-streaming-gate-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

streaming_output="$TEST_TMPDIR/parakeet-eou-320-bench.txt"
finalizer_output="$TEST_TMPDIR/parakeet-v3-ane-bench.txt"
pass_json="$TEST_TMPDIR/pass-result.json"
cat >"$streaming_output" <<'TXT'
backend=parakeet-eou-320 run=0
audio=21.20s load=0.00s processing=0.88s final=0.004s rtfx=24.21
{"audioDurationSeconds":21.2,"backend":"parakeet-eou-320","characterErrorRate":0.6380,"confidence":null,"finalizationSeconds":0.004,"inputPath":"/tmp/chirp.wav","loadSeconds":0,"maxProcessSliceSeconds":0.010,"notes":"True streaming Parakeet EOU 320M.","partialUpdates":25,"referenceText":"Chirp 3: Instant-Custom Voice.","rtfx":24.21,"runIndex":0,"totalProcessingSeconds":0.877,"transcript":"churbre instant custom voice a sterncy personalizer sprachmond old you ingab","wordErrorRate":0.9231}
TXT

cat >"$finalizer_output" <<'TXT'
backend=parakeet-v3-ane run=0
audio=21.20s load=0.00s processing=0.23s final=0.226s rtfx=93.80
{"audioDurationSeconds":21.2,"backend":"parakeet-v3-ane","characterErrorRate":0.0215,"confidence":0.988,"finalizationSeconds":0.226,"inputPath":"/tmp/chirp.wav","loadSeconds":0,"maxProcessSliceSeconds":null,"notes":"Parakeet v3 ANE final paste path.","partialUpdates":0,"referenceText":"Chirp 3: Instant-Custom Voice. Erstellen Sie personalisierte Sprachmodelle mit Audioeingaben von nur zehn Sekunden Länge. Perfekt für Videospiele, Hörbücher, Podcasts und mehr. In über 30 Sprachen verfügbar. Weitere Informationen finden Sie im Media Studio oder in unserer Dokumentation.","rtfx":93.80,"runIndex":0,"totalProcessingSeconds":0.226,"transcript":"Chirp 3: Instant Custom Voice. Erstellen Sie personalisierte Sprachmodelle mit Audioeingaben von nur 10 Sekunden Länge. Perfekt für Videospiele, Hörbücher, Podcasts und mehr. In über 30 Sprachen verfügbar. Weitere Informationen finden Sie im Mediastudio oder in unserer Dokumentation.","wordErrorRate":0.1282}
TXT

"$GATE" \
  --streaming-bench-output "$streaming_output" \
  --expected-streaming-backend parakeet-eou-320 \
  --finalizer-bench-output "$finalizer_output" \
  --expected-finalizer-backend parakeet-v3-ane \
  --json-output "$pass_json" >"$TEST_TMPDIR/pass.txt"
grep -Fq "StreamingPartialReady: true" "$TEST_TMPDIR/pass.txt"
grep -Fq "FinalizerQualityReady: true" "$TEST_TMPDIR/pass.txt"
grep -Fq "HybridQualityReady: true" "$TEST_TMPDIR/pass.txt"
if [[ "$(plutil -extract passed raw -o - "$pass_json")" != "true" ||
      "$(plutil -extract hybridQualityReady raw -o - "$pass_json")" != "true" ||
      "$(plutil -extract streamingPartialReady raw -o - "$pass_json")" != "true" ||
      "$(plutil -extract finalizerQualityReady raw -o - "$pass_json")" != "true" ||
      "$(plutil -extract streamingBackends.0 raw -o - "$pass_json")" != "parakeet-eou-320" ||
      "$(plutil -extract finalizerBackends.0 raw -o - "$pass_json")" != "parakeet-v3-ane" ]]; then
  echo "FAIL: passing hybrid gate JSON mismatch"
  plutil -p "$pass_json"
  exit 1
fi

no_partials_output="$TEST_TMPDIR/no-partials-bench.txt"
cat >"$no_partials_output" <<'TXT'
{"audioDurationSeconds":21.2,"backend":"parakeet-eou-320","characterErrorRate":0.6380,"confidence":null,"finalizationSeconds":0.004,"inputPath":"/tmp/chirp.wav","loadSeconds":0,"maxProcessSliceSeconds":0.010,"notes":"No live partials.","partialUpdates":0,"referenceText":"Chirp 3: Instant-Custom Voice.","rtfx":24.21,"runIndex":0,"totalProcessingSeconds":0.877,"transcript":"churbre instant custom voice","wordErrorRate":0.9231}
TXT
set +e
"$GATE" \
  --streaming-bench-output "$no_partials_output" \
  --finalizer-bench-output "$finalizer_output" \
  --json-output "$TEST_TMPDIR/no-partials.json" >"$TEST_TMPDIR/no-partials.txt" 2>&1
no_partials_status=$?
set -e
if [[ "$no_partials_status" -eq 0 ]]; then
  echo "FAIL: streaming bench without partials unexpectedly passed hybrid gate"
  cat "$TEST_TMPDIR/no-partials.txt"
  exit 1
fi
grep -Fq "StreamingPartialReady: false" "$TEST_TMPDIR/no-partials.txt"
grep -Fq "streaming_report_0_partial_updates_too_low" "$TEST_TMPDIR/no-partials.txt"

slow_finalizer_output="$TEST_TMPDIR/slow-finalizer-bench.txt"
cat >"$slow_finalizer_output" <<'TXT'
{"audioDurationSeconds":21.2,"backend":"stock-v1-gpu","characterErrorRate":0.0215,"confidence":0.988,"finalizationSeconds":3.500,"inputPath":"/tmp/chirp.wav","loadSeconds":0,"maxProcessSliceSeconds":null,"notes":"Accurate but too slow for instant release paste.","partialUpdates":0,"referenceText":"Chirp 3: Instant-Custom Voice.","rtfx":6.0,"runIndex":0,"totalProcessingSeconds":3.500,"transcript":"Chirp 3: Instant-Custom Voice.","wordErrorRate":0.1282}
TXT
set +e
"$GATE" \
  --streaming-bench-output "$streaming_output" \
  --finalizer-bench-output "$slow_finalizer_output" >"$TEST_TMPDIR/slow-finalizer.txt" 2>&1
slow_finalizer_status=$?
set -e
if [[ "$slow_finalizer_status" -eq 0 ]]; then
  echo "FAIL: slow finalizer unexpectedly passed hybrid gate"
  cat "$TEST_TMPDIR/slow-finalizer.txt"
  exit 1
fi
grep -Fq "FinalizerQualityReady: false" "$TEST_TMPDIR/slow-finalizer.txt"
grep -Fq "finalizer_report_0_finalization_too_slow" "$TEST_TMPDIR/slow-finalizer.txt"
grep -Fq "finalizer_report_0_total_processing_too_slow" "$TEST_TMPDIR/slow-finalizer.txt"

bad_finalizer_output="$TEST_TMPDIR/bad-finalizer-bench.txt"
cat >"$bad_finalizer_output" <<'TXT'
{"audioDurationSeconds":21.2,"backend":"parakeet-v3-ane","characterErrorRate":0.2100,"confidence":0.50,"finalizationSeconds":0.226,"inputPath":"/tmp/chirp.wav","loadSeconds":0,"maxProcessSliceSeconds":null,"notes":"Fast but inaccurate final paste path.","partialUpdates":0,"referenceText":"Chirp 3: Instant-Custom Voice.","rtfx":93.80,"runIndex":0,"totalProcessingSeconds":0.226,"transcript":"wrong transcript","wordErrorRate":0.4200}
TXT
set +e
"$GATE" \
  --streaming-bench-output "$streaming_output" \
  --finalizer-bench-output "$bad_finalizer_output" >"$TEST_TMPDIR/bad-finalizer.txt" 2>&1
bad_finalizer_status=$?
set -e
if [[ "$bad_finalizer_status" -eq 0 ]]; then
  echo "FAIL: inaccurate finalizer unexpectedly passed hybrid gate"
  cat "$TEST_TMPDIR/bad-finalizer.txt"
  exit 1
fi
grep -Fq "finalizer_report_0_wer_too_high_or_missing" "$TEST_TMPDIR/bad-finalizer.txt"
grep -Fq "finalizer_report_0_cer_too_high_or_missing" "$TEST_TMPDIR/bad-finalizer.txt"

set +e
"$GATE" \
  --streaming-bench-output "$streaming_output" \
  --expected-streaming-backend nemotron-560 \
  --finalizer-bench-output "$finalizer_output" >"$TEST_TMPDIR/backend-mismatch.txt" 2>&1
backend_mismatch_status=$?
set -e
if [[ "$backend_mismatch_status" -eq 0 ]]; then
  echo "FAIL: backend mismatch unexpectedly passed hybrid gate"
  cat "$TEST_TMPDIR/backend-mismatch.txt"
  exit 1
fi
grep -Fq "streaming_report_0_backend_mismatch" "$TEST_TMPDIR/backend-mismatch.txt"

echo "PASS hybrid_streaming_quality_gate"
