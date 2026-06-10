#!/usr/bin/env bash
set -euo pipefail

INPUTS=()
JSON_OUTPUT=""
EXPECTED_BACKEND="${PRESSTALK_EXPECTED_STREAMING_BENCH_BACKEND:-}"
MIN_PARTIAL_UPDATES="${PRESSTALK_MIN_STREAMING_PARTIAL_UPDATES:-1}"
MIN_RTFX="${PRESSTALK_MIN_STREAMING_RTFX:-1.0}"
MIN_AUDIO_SECONDS="${PRESSTALK_MIN_STREAMING_AUDIO_SECONDS:-3.0}"
MAX_FINALIZATION_SECONDS="${PRESSTALK_MAX_STREAMING_FINALIZATION_SECONDS:-0.25}"
MAX_PROCESS_SLICE_SECONDS="${PRESSTALK_MAX_STREAMING_PROCESS_SLICE_SECONDS:-0.75}"
MAX_WER="${PRESSTALK_MAX_STREAMING_WER:-0.10}"
MAX_CER="${PRESSTALK_MAX_STREAMING_CER:-0.05}"
ALLOW_MISSING_REFERENCE=0

usage() {
  cat <<'EOF'
Usage: presstalk_streaming_bench_quality_gate.sh --bench-output PATH [options]

Reads JSON lines emitted by:
  swift run -c release presstalk-asr-bench ... --json

and verifies that a streaming backend produced live partials, fast finalization,
acceptable slice latency, and acceptable WER/CER against a reference transcript.
This is read-only and does not run models by itself.

Options:
  --bench-output PATH           Text/NDJSON output from presstalk-asr-bench.
                                May be repeated.
  --expected-backend BACKEND    Require every report to use this backend.
  --min-partial-updates N       Default: 1.
  --min-rtfx N                  Default: 1.0.
  --min-audio-seconds N         Default: 3.0.
  --max-finalization-seconds N  Default: 0.25.
  --max-process-slice-seconds N Default: 0.75.
  --max-wer N                   Default: 0.10.
  --max-cer N                   Default: 0.05.
  --allow-missing-reference     Do not require WER/CER fields.
  --json-output PATH            Write machine-readable gate JSON.
  -h, --help                    Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bench-output)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --bench-output" >&2
        exit 2
      fi
      INPUTS+=("$2")
      shift 2
      ;;
    --expected-backend)
      EXPECTED_BACKEND="${2:-}"
      if [[ -z "$EXPECTED_BACKEND" ]]; then
        echo "Missing value for --expected-backend" >&2
        exit 2
      fi
      shift 2
      ;;
    --min-partial-updates)
      MIN_PARTIAL_UPDATES="${2:-}"
      shift 2
      ;;
    --min-rtfx)
      MIN_RTFX="${2:-}"
      shift 2
      ;;
    --min-audio-seconds)
      MIN_AUDIO_SECONDS="${2:-}"
      shift 2
      ;;
    --max-finalization-seconds)
      MAX_FINALIZATION_SECONDS="${2:-}"
      shift 2
      ;;
    --max-process-slice-seconds)
      MAX_PROCESS_SLICE_SECONDS="${2:-}"
      shift 2
      ;;
    --max-wer)
      MAX_WER="${2:-}"
      shift 2
      ;;
    --max-cer)
      MAX_CER="${2:-}"
      shift 2
      ;;
    --allow-missing-reference)
      ALLOW_MISSING_REFERENCE=1
      shift
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

if [[ "${#INPUTS[@]}" -eq 0 ]]; then
  echo "Missing --bench-output PATH" >&2
  usage >&2
  exit 2
fi

valid_number() {
  awk -v value="$1" 'BEGIN { exit !(value ~ /^-?[0-9]+([.][0-9]+)?$/) }'
}

for numeric_arg in \
  "$MIN_PARTIAL_UPDATES" \
  "$MIN_RTFX" \
  "$MIN_AUDIO_SECONDS" \
  "$MAX_FINALIZATION_SECONDS" \
  "$MAX_PROCESS_SLICE_SECONDS" \
  "$MAX_WER" \
  "$MAX_CER"; do
  if ! valid_number "$numeric_arg"; then
    echo "Invalid numeric threshold: $numeric_arg" >&2
    exit 2
  fi
done

RUN_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-streaming-bench-gate.XXXXXX")"
trap 'rm -rf "$RUN_TMPDIR"' EXIT

REPORT_FILES=()
REPORT_BACKENDS=()
FAILURES=()

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

append_failure() {
  FAILURES+=("$1")
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
  local input="$1"
  local line trimmed report_file line_no=0
  if [[ ! -f "$input" ]]; then
    append_failure "bench_output_missing"
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    trimmed="$(trim_line "$line")"
    case "$trimmed" in
      \{*\})
        report_file="$RUN_TMPDIR/report-${#REPORT_FILES[@]}.json"
        printf '%s\n' "$trimmed" >"$report_file"
        if plutil -extract backend raw -o - "$report_file" >/dev/null 2>&1; then
          REPORT_FILES+=("$report_file")
        else
          append_failure "bench_output_line_${line_no}_invalid_json"
        fi
        ;;
    esac
  done <"$input"
}

for input in "${INPUTS[@]}"; do
  extract_reports_from_input "$input"
done

if [[ "${#REPORT_FILES[@]}" -eq 0 ]]; then
  append_failure "bench_reports_missing"
fi

if [[ "${#REPORT_FILES[@]}" -gt 0 ]]; then
  for i in "${!REPORT_FILES[@]}"; do
    report_file="${REPORT_FILES[$i]}"
    backend="$(json_value "$report_file" backend)"
    audio_seconds="$(json_value "$report_file" audioDurationSeconds)"
    final_seconds="$(json_value "$report_file" finalizationSeconds)"
    slice_seconds="$(json_value "$report_file" maxProcessSliceSeconds)"
    rtfx="$(json_value "$report_file" rtfx)"
    partial_updates="$(json_value "$report_file" partialUpdates)"
    wer="$(json_value "$report_file" wordErrorRate)"
    cer="$(json_value "$report_file" characterErrorRate)"
    transcript="$(json_value "$report_file" transcript)"
    reference="$(json_value "$report_file" referenceText)"
    REPORT_BACKENDS+=("${backend:-unknown}")

    if [[ -z "$backend" ]]; then
      append_failure "report_${i}_backend_missing"
    elif [[ -n "$EXPECTED_BACKEND" && "$backend" != "$EXPECTED_BACKEND" ]]; then
      append_failure "report_${i}_backend_mismatch"
    fi
    if [[ -z "$audio_seconds" ]] || ! valid_number "$audio_seconds" || ! num_ge "$audio_seconds" "$MIN_AUDIO_SECONDS"; then
      append_failure "report_${i}_audio_too_short"
    fi
    if [[ -z "$partial_updates" ]] || ! valid_number "$partial_updates" || ! int_ge "$partial_updates" "$MIN_PARTIAL_UPDATES"; then
      append_failure "report_${i}_partial_updates_too_low"
    fi
    if [[ -z "$final_seconds" ]] || ! valid_number "$final_seconds" || ! num_le "$final_seconds" "$MAX_FINALIZATION_SECONDS"; then
      append_failure "report_${i}_finalization_too_slow"
    fi
    if [[ -z "$slice_seconds" ]] || ! valid_number "$slice_seconds" || ! num_le "$slice_seconds" "$MAX_PROCESS_SLICE_SECONDS"; then
      append_failure "report_${i}_process_slice_too_slow_or_missing"
    fi
    if [[ -z "$rtfx" ]] || ! valid_number "$rtfx" || ! num_ge "$rtfx" "$MIN_RTFX"; then
      append_failure "report_${i}_rtfx_too_low"
    fi
    if [[ -z "$transcript" ]]; then
      append_failure "report_${i}_transcript_missing"
    fi
    if [[ "$ALLOW_MISSING_REFERENCE" -eq 0 ]]; then
      if [[ -z "$reference" ]]; then
        append_failure "report_${i}_reference_missing"
      fi
      if [[ -z "$wer" ]] || ! valid_number "$wer" || ! num_le "$wer" "$MAX_WER"; then
        append_failure "report_${i}_wer_too_high_or_missing"
      fi
      if [[ -z "$cer" ]] || ! valid_number "$cer" || ! num_le "$cer" "$MAX_CER"; then
        append_failure "report_${i}_cer_too_high_or_missing"
      fi
    fi
  done
fi

failure_count="${#FAILURES[@]}"
passed=false
streaming_quality_ready=false
if [[ "$failure_count" -eq 0 ]]; then
  passed=true
  streaming_quality_ready=true
fi

echo "PressTalk streaming bench quality gate"
echo "BenchReports: ${#REPORT_FILES[@]}"
echo "ExpectedBackend: ${EXPECTED_BACKEND:-any}"
echo "MinPartialUpdates: $MIN_PARTIAL_UPDATES"
echo "MaxFinalizationSeconds: $MAX_FINALIZATION_SECONDS"
echo "MaxProcessSliceSeconds: $MAX_PROCESS_SLICE_SECONDS"
echo "MaxWER: $MAX_WER"
echo "MaxCER: $MAX_CER"
echo "StreamingQualityReady: $streaming_quality_ready"
if [[ "$failure_count" -gt 0 ]]; then
  echo
  echo "Failures"
  for failure in "${FAILURES[@]}"; do
    echo "- $failure"
  done
fi

if [[ -n "$JSON_OUTPUT" ]]; then
  result_plist="$(mktemp "${TMPDIR:-/tmp}/presstalk-streaming-bench-result.XXXXXX.plist")"
  plutil -create xml1 "$result_plist" >/dev/null
  plutil -insert schemaVersion -string "1" "$result_plist" >/dev/null
  plutil -insert benchOutputs -array "$result_plist" >/dev/null
  for input in "${INPUTS[@]}"; do
    plutil -insert benchOutputs -string "$input" -append "$result_plist" >/dev/null
  done
  plutil -insert expectedBackend -string "${EXPECTED_BACKEND:-any}" "$result_plist" >/dev/null
  plutil -insert reportCount -integer "${#REPORT_FILES[@]}" "$result_plist" >/dev/null
  plutil -insert reportBackends -array "$result_plist" >/dev/null
  if [[ "${#REPORT_BACKENDS[@]}" -gt 0 ]]; then
    for backend in "${REPORT_BACKENDS[@]}"; do
      plutil -insert reportBackends -string "$backend" -append "$result_plist" >/dev/null
    done
  fi
  plutil -insert thresholds -json "{\"minPartialUpdates\":\"$MIN_PARTIAL_UPDATES\",\"minRTFx\":\"$MIN_RTFX\",\"minAudioSeconds\":\"$MIN_AUDIO_SECONDS\",\"maxFinalizationSeconds\":\"$MAX_FINALIZATION_SECONDS\",\"maxProcessSliceSeconds\":\"$MAX_PROCESS_SLICE_SECONDS\",\"maxWER\":\"$MAX_WER\",\"maxCER\":\"$MAX_CER\"}" "$result_plist" >/dev/null
  plutil -insert allowMissingReference -bool "$([[ "$ALLOW_MISSING_REFERENCE" -eq 1 ]] && echo true || echo false)" "$result_plist" >/dev/null
  plutil -insert streamingQualityReady -bool "$streaming_quality_ready" "$result_plist" >/dev/null
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
  echo "StreamingBenchQualityJSON: $JSON_OUTPUT"
fi

if [[ "$passed" != "true" ]]; then
  exit 1
fi
