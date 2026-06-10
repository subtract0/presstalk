#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/presstalk_collect_real_field_smoke.sh"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-real-field-smoke-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

trace_log="$TEST_TMPDIR/presstalk_trace.log"
status_json="$TEST_TMPDIR/runtime-status.json"
output_json="$TEST_TMPDIR/real-field-smoke.json"

cat >"$status_json" <<'JSON'
{
  "runtime": {
    "triggerKey": "fn",
    "asrBackend": "parakeet-v3-ane",
    "streamingASRBackend": "parakeet-eou-320",
    "asrMode": "parakeet_v3_ane_final_pass_with_parakeet_eou_320ms_true_streaming_partials",
    "realtimePartialTranscriptionEnabled": true
  },
  "status": {
    "triggerPath": "Fn / Globe trigger"
  }
}
JSON

cat >"$trace_log" <<'LOG'
[2026-06-10T21:23:26.921Z] Input debug: cg flagsChanged keyCode=63 trigger=fn pressed=true
[2026-06-10T21:23:26.925Z] 🎙️ Fn / Globe pressed: recording started
[2026-06-10T21:23:27.042Z] FluidAudio true streaming loop started backend=parakeet-eou-320 poll_seconds=0.15
[2026-06-10T21:23:31.663Z] Realtime partial transcript revision=1: report
[2026-06-10T21:23:38.786Z] Realtime partial transcript revision=11: report did it auto insert rough latency after release the inserted text pastes here
[2026-06-10T21:23:46.275Z] Input debug: cg flagsChanged keyCode=63 trigger=fn pressed=false
[2026-06-10T21:23:46.278Z] 🛑 Fn / Globe released: recording ended
[2026-06-10T21:23:46.431Z] Audio capture frozen samples=308800 duration_seconds=19.30 rms=0.02161 peak=0.32689 input_device=Shure MV7i [id=152, transport=usb, channels=2]
[2026-06-10T21:23:46.565Z] Parakeet v3 ASR pass completed samples=308800 inference_seconds=0.133 confidence=0.927 language=auto
[2026-06-10T21:23:46.565Z] Parakeet v3 ANE transcript: Report Did it auto insert? Rough latency after release? The inserted text pasted here.
[2026-06-10T21:23:46.566Z] Parakeet v3 ANE transcript accepted but quality fallback requested reason=low_confidence confidence=0.927 threshold=0.960
[2026-06-10T21:23:47.596Z] Primary offline Whisper transcript: Report. Did it auto-insert? Rough latency after release? The inserted text paces here.
[2026-06-10T21:23:47.597Z] Using offline Whisper transcript as final transcript
[2026-06-10T21:23:47.597Z] 📝 Transkription abgeschlossen: Report. Did it auto-insert? Rough latency after release? The inserted text paces here.
[2026-06-10T21:23:47.623Z] Paste menu pressed target_pid=39451
[2026-06-10T21:23:47.623Z] Dictation inserted method=ax_menu_paste
LOG

"$HELPER" \
  --trace-log "$trace_log" \
  --status-json "$status_json" \
  --json-output "$output_json" \
  --user-report "all great" >"$TEST_TMPDIR/output.txt"

test -s "$output_json"
grep -Fq "Success: true" "$TEST_TMPDIR/output.txt"
grep -Fq "ReleaseToInsertMs: 1345" "$TEST_TMPDIR/output.txt"

if [[ "$(plutil -extract success raw -o - "$output_json")" != "true" ||
      "$(plutil -extract targetCaptureSuccess raw -o - "$output_json")" != "true" ||
      "$(plutil -extract reason raw -o - "$output_json")" != "trace_inserted" ||
      "$(plutil -extract userReport raw -o - "$output_json")" != "all great" ||
      "$(plutil -extract observed.releaseToInsertMs raw -o - "$output_json")" != "1345" ||
      "$(plutil -extract observed.partialUpdateCount raw -o - "$output_json")" != "2" ||
      "$(plutil -extract observed.finalizer raw -o - "$output_json")" != "offline_whisper" ||
      "$(plutil -extract observed.insertionMethod raw -o - "$output_json")" != "ax_menu_paste" ||
      "$(plutil -extract observed.whisperFallbackRequested raw -o - "$output_json")" != "true" ||
      "$(plutil -extract runtime.streamingASRBackend raw -o - "$output_json")" != "parakeet-eou-320" ]]; then
  echo "FAIL: unexpected real-field smoke JSON"
  plutil -p "$output_json"
  exit 1
fi

missing_output="$TEST_TMPDIR/missing.json"
cat >"$trace_log" <<'LOG'
[2026-06-10T21:23:47.623Z] unrelated
LOG
if "$HELPER" --trace-log "$trace_log" --status-json "$status_json" --json-output "$missing_output" >"$TEST_TMPDIR/missing.txt" 2>&1; then
  echo "FAIL: collector unexpectedly passed without a session"
  exit 1
fi
grep -Fq "No PressTalk dictation session found" "$TEST_TMPDIR/missing.txt"

echo "PASS real_field_smoke_collector"
