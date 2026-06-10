#!/usr/bin/env bash
set -euo pipefail

STREAMING_INPUTS=()
FINALIZER_INPUTS=()
JSON_OUTPUT=""
EXPECTED_STREAMING_BACKEND="${PRESSTALK_EXPECTED_HYBRID_STREAMING_BACKEND:-}"
EXPECTED_FINALIZER_BACKEND="${PRESSTALK_EXPECTED_HYBRID_FINALIZER_BACKEND:-}"
MIN_STREAMING_PARTIAL_UPDATES="${PRESSTALK_MIN_HYBRID_STREAMING_PARTIAL_UPDATES:-1}"
MIN_STREAMING_RTFX="${PRESSTALK_MIN_HYBRID_STREAMING_RTFX:-1.0}"
MIN_STREAMING_AUDIO_SECONDS="${PRESSTALK_MIN_HYBRID_STREAMING_AUDIO_SECONDS:-3.0}"
MAX_STREAMING_FINALIZATION_SECONDS="${PRESSTALK_MAX_HYBRID_STREAMING_FINALIZATION_SECONDS:-0.25}"
MAX_STREAMING_PROCESS_SLICE_SECONDS="${PRESSTALK_MAX_HYBRID_STREAMING_PROCESS_SLICE_SECONDS:-0.75}"
MIN_FINALIZER_RTFX="${PRESSTALK_MIN_HYBRID_FINALIZER_RTFX:-1.0}"
MIN_FINALIZER_AUDIO_SECONDS="${PRESSTALK_MIN_HYBRID_FINALIZER_AUDIO_SECONDS:-3.0}"
MAX_FINALIZER_FINALIZATION_SECONDS="${PRESSTALK_MAX_HYBRID_FINALIZER_FINALIZATION_SECONDS:-0.75}"
MAX_FINALIZER_TOTAL_SECONDS="${PRESSTALK_MAX_HYBRID_FINALIZER_TOTAL_SECONDS:-0.75}"
MAX_FINALIZER_WER="${PRESSTALK_MAX_HYBRID_FINALIZER_WER:-0.15}"
MAX_FINALIZER_CER="${PRESSTALK_MAX_HYBRID_FINALIZER_CER:-0.05}"

usage() {
  cat <<'EOF'
Usage: presstalk_hybrid_streaming_quality_gate.sh --streaming-bench-output PATH --finalizer-bench-output PATH [options]

Reads JSON lines emitted by:
  swift run -c release presstalk-asr-bench ... --json

and verifies the practical hybrid dictation architecture:
  1. a streaming backend proves live partials and low latency for the HUD
  2. a finalizer backend proves paste-quality transcript accuracy and speed

This is read-only and does not run models by itself.

Options:
  --streaming-bench-output PATH  NDJSON output from the live streaming backend.
                                 May be repeated.
  --finalizer-bench-output PATH  NDJSON output from the final paste backend.
                                 May be repeated.
  --expected-streaming-backend B Require every streaming report to use B.
  --expected-finalizer-backend B Require every finalizer report to use B.
  --min-streaming-partials N     Default: 1.
  --min-streaming-rtfx N         Default: 1.0.
  --min-streaming-audio-seconds N
                                 Default: 3.0.
  --max-streaming-finalization-seconds N
                                 Default: 0.25.
  --max-streaming-process-slice-seconds N
                                 Default: 0.75.
  --min-finalizer-rtfx N         Default: 1.0.
  --min-finalizer-audio-seconds N
                                 Default: 3.0.
  --max-finalizer-finalization-seconds N
                                 Default: 0.75.
  --max-finalizer-total-seconds N
                                 Default: 0.75.
  --max-finalizer-wer N          Default: 0.15.
  --max-finalizer-cer N          Default: 0.05.
  --json-output PATH             Write machine-readable gate JSON.
  -h, --help                     Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --streaming-bench-output)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --streaming-bench-output" >&2
        exit 2
      fi
      STREAMING_INPUTS+=("$2")
      shift 2
      ;;
    --finalizer-bench-output)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --finalizer-bench-output" >&2
        exit 2
      fi
      FINALIZER_INPUTS+=("$2")
      shift 2
      ;;
    --expected-streaming-backend)
      EXPECTED_STREAMING_BACKEND="${2:-}"
      if [[ -z "$EXPECTED_STREAMING_BACKEND" ]]; then
        echo "Missing value for --expected-streaming-backend" >&2
        exit 2
      fi
      shift 2
      ;;
    --expected-finalizer-backend)
      EXPECTED_FINALIZER_BACKEND="${2:-}"
      if [[ -z "$EXPECTED_FINALIZER_BACKEND" ]]; then
        echo "Missing value for --expected-finalizer-backend" >&2
        exit 2
      fi
      shift 2
      ;;
    --min-streaming-partials)
      MIN_STREAMING_PARTIAL_UPDATES="${2:-}"
      shift 2
      ;;
    --min-streaming-rtfx)
      MIN_STREAMING_RTFX="${2:-}"
      shift 2
      ;;
    --min-streaming-audio-seconds)
      MIN_STREAMING_AUDIO_SECONDS="${2:-}"
      shift 2
      ;;
    --max-streaming-finalization-seconds)
      MAX_STREAMING_FINALIZATION_SECONDS="${2:-}"
      shift 2
      ;;
    --max-streaming-process-slice-seconds)
      MAX_STREAMING_PROCESS_SLICE_SECONDS="${2:-}"
      shift 2
      ;;
    --min-finalizer-rtfx)
      MIN_FINALIZER_RTFX="${2:-}"
      shift 2
      ;;
    --min-finalizer-audio-seconds)
      MIN_FINALIZER_AUDIO_SECONDS="${2:-}"
      shift 2
      ;;
    --max-finalizer-finalization-seconds)
      MAX_FINALIZER_FINALIZATION_SECONDS="${2:-}"
      shift 2
      ;;
    --max-finalizer-total-seconds)
      MAX_FINALIZER_TOTAL_SECONDS="${2:-}"
      shift 2
      ;;
    --max-finalizer-wer)
      MAX_FINALIZER_WER="${2:-}"
      shift 2
      ;;
    --max-finalizer-cer)
      MAX_FINALIZER_CER="${2:-}"
      shift 2
      ;;
    --json-output)
      JSON_OUTPUT="${2:-}"
      if [[ -z "$JSON_OUTPUT" ]]; then
        echo "Missing value for --json-output" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${#STREAMING_INPUTS[@]}" -eq 0 ]]; then
  echo "Missing --streaming-bench-output PATH" >&2
  usage >&2
  exit 2
fi
if [[ "${#FINALIZER_INPUTS[@]}" -eq 0 ]]; then
  echo "Missing --finalizer-bench-output PATH" >&2
  usage >&2
  exit 2
fi

valid_number() {
  awk -v value="$1" 'BEGIN { exit !(value ~ /^-?[0-9]+([.][0-9]+)?$/) }'
}

for numeric_arg in \
  "$MIN_STREAMING_PARTIAL_UPDATES" \
  "$MIN_STREAMING_RTFX" \
  "$MIN_STREAMING_AUDIO_SECONDS" \
  "$MAX_STREAMING_FINALIZATION_SECONDS" \
  "$MAX_STREAMING_PROCESS_SLICE_SECONDS" \
  "$MIN_FINALIZER_RTFX" \
  "$MIN_FINALIZER_AUDIO_SECONDS" \
  "$MAX_FINALIZER_FINALIZATION_SECONDS" \
  "$MAX_FINALIZER_TOTAL_SECONDS" \
  "$MAX_FINALIZER_WER" \
  "$MAX_FINALIZER_CER"; do
  if ! valid_number "$numeric_arg"; then
    echo "Invalid numeric threshold: $numeric_arg" >&2
    exit 2
  fi
done

RUN_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-hybrid-streaming-gate.XXXXXX")"
trap 'rm -rf "$RUN_TMPDIR"' EXIT

STREAMING_REPORT_FILES=()
FINALIZER_REPORT_FILES=()
STREAMING_REPORT_BACKENDS=()
FINALIZER_REPORT_BACKENDS=()
FAILURES=()
streaming_partial_ready=true
finalizer_quality_ready=true

trim_line() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  printf '%s' "$line"
}

json_value() {
  local file="$1"
  local key="$2"
  local value
  value="$(plutil -extract "$key" raw -o - "$file" 2>/dev/null || true)"
  case "$value" in
    null|"<null>") value="" ;;
  esac
  printf '%s' "$value"
}

append_streaming_failure() {
  FAILURES+=("$1")
  streaming_partial_ready=false
}

append_finalizer_failure() {
  FAILURES+=("$1")
  finalizer_quality_ready=false
}

num_le() {
  awk -v value="$1" -v limit="$2" 'BEGIN { exit !(value <= limit) }'
}

num_ge() {
  awk -v value="$1" -v limit="$2" 'BEGIN { exit !(value >= limit) }'
}

int_ge() {
  awk -v value="$1" -v limit="$2" 'BEGIN { exit !(value >= limit) }'
}

extract_reports_from_input() {
  local kind="$1"
  local input="$2"
  local line trimmed report_file line_no=0 index
  if [[ ! -f "$input" ]]; then
    if [[ "$kind" == "streaming" ]]; then
      append_streaming_failure "streaming_bench_output_missing"
    else
      append_finalizer_failure "finalizer_bench_output_missing"
    fi
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    trimmed="$(trim_line "$line")"
    case "$trimmed" in
      \{*\})
        if [[ "$kind" == "streaming" ]]; then
          index="${#STREAMING_REPORT_FILES[@]}"
        else
          index="${#FINALIZER_REPORT_FILES[@]}"
        fi
        report_file="$RUN_TMPDIR/${kind}-report-${index}.json"
        printf '%s\n' "$trimmed" >"$report_file"
        if plutil -extract backend raw -o - "$report_file" >/dev/null 2>&1; then
          if [[ "$kind" == "streaming" ]]; then
            STREAMING_REPORT_FILES+=("$report_file")
          else
            FINALIZER_REPORT_FILES+=("$report_file")
          fi
        else
          if [[ "$kind" == "streaming" ]]; then
            append_streaming_failure "streaming_bench_output_line_${line_no}_invalid_json"
          else
            append_finalizer_failure "finalizer_bench_output_line_${line_no}_invalid_json"
          fi
        fi
        ;;
    esac
  done <"$input"
}

for input in "${STREAMING_INPUTS[@]}"; do
  extract_reports_from_input streaming "$input"
done
for input in "${FINALIZER_INPUTS[@]}"; do
  extract_reports_from_input finalizer "$input"
done

if [[ "${#STREAMING_REPORT_FILES[@]}" -eq 0 ]]; then
  append_streaming_failure "streaming_bench_reports_missing"
fi
if [[ "${#FINALIZER_REPORT_FILES[@]}" -eq 0 ]]; then
  append_finalizer_failure "finalizer_bench_reports_missing"
fi

if [[ "${#STREAMING_REPORT_FILES[@]}" -gt 0 ]]; then
  for i in "${!STREAMING_REPORT_FILES[@]}"; do
    report_file="${STREAMING_REPORT_FILES[$i]}"
    backend="$(json_value "$report_file" backend)"
    audio_seconds="$(json_value "$report_file" audioDurationSeconds)"
    final_seconds="$(json_value "$report_file" finalizationSeconds)"
    slice_seconds="$(json_value "$report_file" maxProcessSliceSeconds)"
    rtfx="$(json_value "$report_file" rtfx)"
    partial_updates="$(json_value "$report_file" partialUpdates)"
    transcript="$(json_value "$report_file" transcript)"
    STREAMING_REPORT_BACKENDS+=("${backend:-unknown}")

    if [[ -z "$backend" ]]; then
      append_streaming_failure "streaming_report_${i}_backend_missing"
    elif [[ -n "$EXPECTED_STREAMING_BACKEND" && "$backend" != "$EXPECTED_STREAMING_BACKEND" ]]; then
      append_streaming_failure "streaming_report_${i}_backend_mismatch"
    fi
    if [[ -z "$audio_seconds" ]] || ! valid_number "$audio_seconds" || ! num_ge "$audio_seconds" "$MIN_STREAMING_AUDIO_SECONDS"; then
      append_streaming_failure "streaming_report_${i}_audio_too_short"
    fi
    if [[ -z "$partial_updates" ]] || ! valid_number "$partial_updates" || ! int_ge "$partial_updates" "$MIN_STREAMING_PARTIAL_UPDATES"; then
      append_streaming_failure "streaming_report_${i}_partial_updates_too_low"
    fi
    if [[ -z "$final_seconds" ]] || ! valid_number "$final_seconds" || ! num_le "$final_seconds" "$MAX_STREAMING_FINALIZATION_SECONDS"; then
      append_streaming_failure "streaming_report_${i}_finalization_too_slow"
    fi
    if [[ -z "$slice_seconds" ]] || ! valid_number "$slice_seconds" || ! num_le "$slice_seconds" "$MAX_STREAMING_PROCESS_SLICE_SECONDS"; then
      append_streaming_failure "streaming_report_${i}_process_slice_too_slow_or_missing"
    fi
    if [[ -z "$rtfx" ]] || ! valid_number "$rtfx" || ! num_ge "$rtfx" "$MIN_STREAMING_RTFX"; then
      append_streaming_failure "streaming_report_${i}_rtfx_too_low"
    fi
    if [[ -z "$transcript" ]]; then
      append_streaming_failure "streaming_report_${i}_transcript_missing"
    fi
  done
fi

if [[ "${#FINALIZER_REPORT_FILES[@]}" -gt 0 ]]; then
  for i in "${!FINALIZER_REPORT_FILES[@]}"; do
    report_file="${FINALIZER_REPORT_FILES[$i]}"
    backend="$(json_value "$report_file" backend)"
    audio_seconds="$(json_value "$report_file" audioDurationSeconds)"
    final_seconds="$(json_value "$report_file" finalizationSeconds)"
    total_seconds="$(json_value "$report_file" totalProcessingSeconds)"
    rtfx="$(json_value "$report_file" rtfx)"
    wer="$(json_value "$report_file" wordErrorRate)"
    cer="$(json_value "$report_file" characterErrorRate)"
    transcript="$(json_value "$report_file" transcript)"
    reference="$(json_value "$report_file" referenceText)"
    FINALIZER_REPORT_BACKENDS+=("${backend:-unknown}")

    if [[ -z "$backend" ]]; then
      append_finalizer_failure "finalizer_report_${i}_backend_missing"
    elif [[ -n "$EXPECTED_FINALIZER_BACKEND" && "$backend" != "$EXPECTED_FINALIZER_BACKEND" ]]; then
      append_finalizer_failure "finalizer_report_${i}_backend_mismatch"
    fi
    if [[ -z "$audio_seconds" ]] || ! valid_number "$audio_seconds" || ! num_ge "$audio_seconds" "$MIN_FINALIZER_AUDIO_SECONDS"; then
      append_finalizer_failure "finalizer_report_${i}_audio_too_short"
    fi
    if [[ -z "$final_seconds" ]] || ! valid_number "$final_seconds" || ! num_le "$final_seconds" "$MAX_FINALIZER_FINALIZATION_SECONDS"; then
      append_finalizer_failure "finalizer_report_${i}_finalization_too_slow"
    fi
    if [[ -z "$total_seconds" ]] || ! valid_number "$total_seconds" || ! num_le "$total_seconds" "$MAX_FINALIZER_TOTAL_SECONDS"; then
      append_finalizer_failure "finalizer_report_${i}_total_processing_too_slow"
    fi
    if [[ -z "$rtfx" ]] || ! valid_number "$rtfx" || ! num_ge "$rtfx" "$MIN_FINALIZER_RTFX"; then
      append_finalizer_failure "finalizer_report_${i}_rtfx_too_low"
    fi
    if [[ -z "$transcript" ]]; then
      append_finalizer_failure "finalizer_report_${i}_transcript_missing"
    fi
    if [[ -z "$reference" ]]; then
      append_finalizer_failure "finalizer_report_${i}_reference_missing"
    fi
    if [[ -z "$wer" ]] || ! valid_number "$wer" || ! num_le "$wer" "$MAX_FINALIZER_WER"; then
      append_finalizer_failure "finalizer_report_${i}_wer_too_high_or_missing"
    fi
    if [[ -z "$cer" ]] || ! valid_number "$cer" || ! num_le "$cer" "$MAX_FINALIZER_CER"; then
      append_finalizer_failure "finalizer_report_${i}_cer_too_high_or_missing"
    fi
  done
fi

failure_count="${#FAILURES[@]}"
passed=false
hybrid_quality_ready=false
if [[ "$failure_count" -eq 0 ]]; then
  passed=true
  hybrid_quality_ready=true
fi

echo "PressTalk hybrid streaming quality gate"
echo "StreamingBenchReports: ${#STREAMING_REPORT_FILES[@]}"
echo "FinalizerBenchReports: ${#FINALIZER_REPORT_FILES[@]}"
echo "ExpectedStreamingBackend: ${EXPECTED_STREAMING_BACKEND:-any}"
echo "ExpectedFinalizerBackend: ${EXPECTED_FINALIZER_BACKEND:-any}"
echo "StreamingPartialReady: $streaming_partial_ready"
echo "FinalizerQualityReady: $finalizer_quality_ready"
echo "HybridQualityReady: $hybrid_quality_ready"
if [[ "$failure_count" -gt 0 ]]; then
  echo
  echo "Failures"
  for failure in "${FAILURES[@]}"; do
    echo "- $failure"
  done
fi

if [[ -n "$JSON_OUTPUT" ]]; then
  result_plist="$(mktemp "${TMPDIR:-/tmp}/presstalk-hybrid-streaming-result.XXXXXX.plist")"
  plutil -create xml1 "$result_plist" >/dev/null
  plutil -insert schemaVersion -string "1" "$result_plist" >/dev/null
  plutil -insert streamingBenchOutputs -array "$result_plist" >/dev/null
  for input in "${STREAMING_INPUTS[@]}"; do
    plutil -insert streamingBenchOutputs -string "$input" -append "$result_plist" >/dev/null
  done
  plutil -insert finalizerBenchOutputs -array "$result_plist" >/dev/null
  for input in "${FINALIZER_INPUTS[@]}"; do
    plutil -insert finalizerBenchOutputs -string "$input" -append "$result_plist" >/dev/null
  done
  plutil -insert expectedStreamingBackend -string "${EXPECTED_STREAMING_BACKEND:-any}" "$result_plist" >/dev/null
  plutil -insert expectedFinalizerBackend -string "${EXPECTED_FINALIZER_BACKEND:-any}" "$result_plist" >/dev/null
  plutil -insert streamingReportCount -integer "${#STREAMING_REPORT_FILES[@]}" "$result_plist" >/dev/null
  plutil -insert finalizerReportCount -integer "${#FINALIZER_REPORT_FILES[@]}" "$result_plist" >/dev/null
  plutil -insert streamingBackends -array "$result_plist" >/dev/null
  for backend in "${STREAMING_REPORT_BACKENDS[@]}"; do
    plutil -insert streamingBackends -string "$backend" -append "$result_plist" >/dev/null
  done
  plutil -insert finalizerBackends -array "$result_plist" >/dev/null
  for backend in "${FINALIZER_REPORT_BACKENDS[@]}"; do
    plutil -insert finalizerBackends -string "$backend" -append "$result_plist" >/dev/null
  done
  plutil -insert streamingThresholds -json "{\"minPartialUpdates\":\"$MIN_STREAMING_PARTIAL_UPDATES\",\"minRTFx\":\"$MIN_STREAMING_RTFX\",\"minAudioSeconds\":\"$MIN_STREAMING_AUDIO_SECONDS\",\"maxFinalizationSeconds\":\"$MAX_STREAMING_FINALIZATION_SECONDS\",\"maxProcessSliceSeconds\":\"$MAX_STREAMING_PROCESS_SLICE_SECONDS\"}" "$result_plist" >/dev/null
  plutil -insert finalizerThresholds -json "{\"minRTFx\":\"$MIN_FINALIZER_RTFX\",\"minAudioSeconds\":\"$MIN_FINALIZER_AUDIO_SECONDS\",\"maxFinalizationSeconds\":\"$MAX_FINALIZER_FINALIZATION_SECONDS\",\"maxTotalSeconds\":\"$MAX_FINALIZER_TOTAL_SECONDS\",\"maxWER\":\"$MAX_FINALIZER_WER\",\"maxCER\":\"$MAX_FINALIZER_CER\"}" "$result_plist" >/dev/null
  plutil -insert streamingPartialReady -bool "$streaming_partial_ready" "$result_plist" >/dev/null
  plutil -insert finalizerQualityReady -bool "$finalizer_quality_ready" "$result_plist" >/dev/null
  plutil -insert hybridQualityReady -bool "$hybrid_quality_ready" "$result_plist" >/dev/null
  plutil -insert passed -bool "$passed" "$result_plist" >/dev/null
  plutil -insert failureCount -integer "$failure_count" "$result_plist" >/dev/null
  plutil -insert failures -array "$result_plist" >/dev/null
  if [[ "$failure_count" -gt 0 ]]; then
    for failure in "${FAILURES[@]}"; do
      plutil -insert failures -string "$failure" -append "$result_plist" >/dev/null
    done
  fi
  mkdir -p "$(dirname "$JSON_OUTPUT")"
  plutil -convert json -r -o "$JSON_OUTPUT" "$result_plist"
  rm -f "$result_plist"
  echo
  echo "HybridStreamingQualityJSON: $JSON_OUTPUT"
fi

if [[ "$passed" != "true" ]]; then
  exit 1
fi
