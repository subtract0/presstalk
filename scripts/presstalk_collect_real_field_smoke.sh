#!/usr/bin/env bash
set -euo pipefail

TRACE_LOG="${PRESSTALK_TRACE_LOG:-$HOME/Library/Logs/presstalk_trace.log}"
STATUS_JSON="${PRESSTALK_STATUS_JSON:-$HOME/Library/Application Support/JarvisTap/runtime-status.json}"
DIAGNOSTICS_DIR="${PRESSTALK_DIAGNOSTICS_DIR:-$HOME/Library/Application Support/JarvisTap/Diagnostics}"
JSON_OUTPUT_PATH=""
USER_REPORT="${PRESSTALK_REAL_FIELD_SMOKE_USER_REPORT:-}"

usage() {
  cat <<EOF
Usage: presstalk-collect-real-field-smoke.sh [options]

Collects the latest real focused-field PressTalk dictation session from the
trace log and writes a JSON diagnostic receipt. This is read-only: it does not
record audio, press keys, paste text, start PressTalk, or open System Settings.

Options:
  --trace-log PATH       Trace log. Default: $TRACE_LOG
  --status-json PATH     Runtime status JSON. Default: $STATUS_JSON
  --diagnostics-dir DIR  Output diagnostics directory. Default: $DIAGNOSTICS_DIR
  --json-output PATH     Write this exact JSON path instead of an auto-named
                         real-field-smoke-*.json file.
  --user-report TEXT     Optional short human report, for example "all great".
  -h, --help             Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace-log)
      TRACE_LOG="${2:-}"
      if [[ -z "$TRACE_LOG" ]]; then
        echo "Missing value for --trace-log" >&2
        exit 2
      fi
      shift 2
      ;;
    --status-json)
      STATUS_JSON="${2:-}"
      if [[ -z "$STATUS_JSON" ]]; then
        echo "Missing value for --status-json" >&2
        exit 2
      fi
      shift 2
      ;;
    --diagnostics-dir)
      DIAGNOSTICS_DIR="${2:-}"
      if [[ -z "$DIAGNOSTICS_DIR" ]]; then
        echo "Missing value for --diagnostics-dir" >&2
        exit 2
      fi
      shift 2
      ;;
    --json-output)
      JSON_OUTPUT_PATH="${2:-}"
      if [[ -z "$JSON_OUTPUT_PATH" ]]; then
        echo "Missing value for --json-output" >&2
        exit 2
      fi
      shift 2
      ;;
    --user-report)
      USER_REPORT="${2:-}"
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

if [[ ! -f "$TRACE_LOG" ]]; then
  echo "Missing trace log: $TRACE_LOG" >&2
  exit 1
fi

status_value() {
  local key_path="$1"
  if [[ -f "$STATUS_JSON" ]]; then
    plutil -extract "$key_path" raw -o - "$STATUS_JSON" 2>/dev/null || true
  fi
}

plist_insert_string() {
  local plist="$1"
  local key="$2"
  local value="${3:-}"
  plutil -insert "$key" -string "${value:-unknown}" "$plist" >/dev/null
}

plist_insert_bool() {
  local plist="$1"
  local key="$2"
  local value="${3:-false}"
  case "$value" in
    true|1|yes) plutil -insert "$key" -bool true "$plist" >/dev/null ;;
    *) plutil -insert "$key" -bool false "$plist" >/dev/null ;;
  esac
}

plist_insert_number_or_string() {
  local plist="$1"
  local key="$2"
  local value="${3:-}"
  if [[ "$value" =~ ^-?[0-9]+$ ]]; then
    plutil -insert "$key" -integer "$value" "$plist" >/dev/null
  elif [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    plutil -insert "$key" -float "$value" "$plist" >/dev/null
  else
    plutil -insert "$key" -string "${value:-unknown}" "$plist" >/dev/null
  fi
}

parse_output="$(
  awk '
    function timestamp(line, tmp) {
      tmp = line
      sub(/^\[/, "", tmp)
      sub(/\].*$/, "", tmp)
      return tmp
    }
    function ts_ms(ts, parts, t, s) {
      split(ts, parts, "T")
      split(parts[2], t, ":")
      s = t[3]
      sub(/Z$/, "", s)
      return int(((t[1] * 3600) + (t[2] * 60) + s) * 1000)
    }
    function token(line, name, tmp) {
      tmp = line
      if (index(tmp, name "=") == 0) {
        return ""
      }
      sub(".*" name "=", "", tmp)
      sub(/[[:space:]].*$/, "", tmp)
      return tmp
    }
    function after(line, marker, tmp) {
      tmp = line
      sub(".*" marker, "", tmp)
      sub(/^[[:space:]]+/, "", tmp)
      return tmp
    }
    function clear_session() {
      pressed_at = ""
      released_at = ""
      inserted_at = ""
      release_to_insert_ms = ""
      held_ms = ""
      audio_duration = ""
      streaming_backend = ""
      asr_mode = ""
      partial_count = 0
      last_partial = ""
      parakeet_inference = ""
      parakeet_confidence = ""
      parakeet_transcript = ""
      whisper_fallback_requested = "false"
      whisper_transcript = ""
      finalizer = ""
      final_transcript = ""
      inserted = "false"
      insertion_method = ""
      paste_command_posted = "false"
      capture_frozen = "false"
      session_seen = "false"
    }
    function reset_session() {
      clear_session()
      pressed_at = timestamp($0)
      session_seen = "true"
    }

    /Startup initiated trace_log=/ {
      latest_startup_at = timestamp($0)
      startup_seen = "true"
      clear_session()
      next
    }

    /pressed: recording started|armed: recording started/ {
      reset_session()
      next
    }

    session_seen != "true" {
      next
    }

    /released: recording ended/ {
      released_at = timestamp($0)
      if (pressed_at != "") {
        held_ms = ts_ms(released_at) - ts_ms(pressed_at)
      }
    }
    /FluidAudio true streaming loop started backend=/ {
      streaming_backend = token($0, "backend")
    }
    /Realtime partial transcript revision=/ {
      partial_count += 1
      last_partial = after($0, ":")
    }
    /Audio capture frozen/ {
      capture_frozen = "true"
      audio_duration = token($0, "duration_seconds")
    }
    /Parakeet v3 ASR pass completed/ {
      parakeet_inference = token($0, "inference_seconds")
      parakeet_confidence = token($0, "confidence")
    }
    /Parakeet v3 ANE transcript:/ {
      parakeet_transcript = after($0, "Parakeet v3 ANE transcript:")
    }
    /quality fallback requested/ {
      whisper_fallback_requested = "true"
    }
    /Primary offline Whisper transcript:/ {
      whisper_transcript = after($0, "Primary offline Whisper transcript:")
    }
    /Using offline Whisper transcript as final transcript/ {
      finalizer = "offline_whisper"
    }
    /Using Parakeet v3 ANE transcript as final transcript/ {
      finalizer = "parakeet_v3_ane"
    }
    /Transkription abgeschlossen:/ {
      final_transcript = after($0, "Transkription abgeschlossen:")
    }
    /Paste menu pressed|Dictation paste command posted/ {
      paste_command_posted = "true"
    }
    /Dictation inserted method=/ {
      inserted = "true"
      inserted_at = timestamp($0)
      insertion_method = token($0, "method")
      if (released_at != "") {
        release_to_insert_ms = ts_ms(inserted_at) - ts_ms(released_at)
      }
    }

    END {
      if (session_seen != "true") {
        exit 3
      }
      printf "appStartedAt\t%s\n", latest_startup_at
      printf "pressedAt\t%s\n", pressed_at
      printf "releasedAt\t%s\n", released_at
      printf "insertedAt\t%s\n", inserted_at
      printf "heldMs\t%s\n", held_ms
      printf "releaseToInsertMs\t%s\n", release_to_insert_ms
      printf "audioDurationSeconds\t%s\n", audio_duration
      printf "streamingASRBackendObserved\t%s\n", streaming_backend
      printf "partialUpdateCount\t%s\n", partial_count
      printf "lastPartialTranscript\t%s\n", last_partial
      printf "captureFrozen\t%s\n", capture_frozen
      printf "parakeetInferenceSeconds\t%s\n", parakeet_inference
      printf "parakeetConfidence\t%s\n", parakeet_confidence
      printf "parakeetTranscript\t%s\n", parakeet_transcript
      printf "whisperFallbackRequested\t%s\n", whisper_fallback_requested
      printf "whisperTranscript\t%s\n", whisper_transcript
      printf "finalizer\t%s\n", finalizer
      printf "finalTranscript\t%s\n", final_transcript
      printf "pasteCommandPosted\t%s\n", paste_command_posted
      printf "inserted\t%s\n", inserted
      printf "insertionMethod\t%s\n", insertion_method
    }
  ' "$TRACE_LOG"
)" || {
  status=$?
  if [[ "$status" == "3" ]]; then
    echo "No PressTalk dictation session found in trace log: $TRACE_LOG" >&2
  else
    echo "Failed to parse trace log: $TRACE_LOG" >&2
  fi
  exit 1
}

pressed_at=""
app_started_at=""
released_at=""
inserted_at=""
held_ms=""
release_to_insert_ms=""
audio_duration_seconds=""
streaming_asr_backend_observed=""
partial_update_count=""
last_partial_transcript=""
capture_frozen="false"
parakeet_inference_seconds=""
parakeet_confidence=""
parakeet_transcript=""
whisper_fallback_requested="false"
whisper_transcript=""
finalizer=""
final_transcript=""
paste_command_posted="false"
inserted="false"
insertion_method=""

while IFS=$'\t' read -r key value; do
  case "$key" in
    appStartedAt) app_started_at="$value" ;;
    pressedAt) pressed_at="$value" ;;
    releasedAt) released_at="$value" ;;
    insertedAt) inserted_at="$value" ;;
    heldMs) held_ms="$value" ;;
    releaseToInsertMs) release_to_insert_ms="$value" ;;
    audioDurationSeconds) audio_duration_seconds="$value" ;;
    streamingASRBackendObserved) streaming_asr_backend_observed="$value" ;;
    partialUpdateCount) partial_update_count="$value" ;;
    lastPartialTranscript) last_partial_transcript="$value" ;;
    captureFrozen) capture_frozen="$value" ;;
    parakeetInferenceSeconds) parakeet_inference_seconds="$value" ;;
    parakeetConfidence) parakeet_confidence="$value" ;;
    parakeetTranscript) parakeet_transcript="$value" ;;
    whisperFallbackRequested) whisper_fallback_requested="$value" ;;
    whisperTranscript) whisper_transcript="$value" ;;
    finalizer) finalizer="$value" ;;
    finalTranscript) final_transcript="$value" ;;
    pasteCommandPosted) paste_command_posted="$value" ;;
    inserted) inserted="$value" ;;
    insertionMethod) insertion_method="$value" ;;
  esac
done <<<"$parse_output"

success="false"
target_capture_success="false"
reason="trace_incomplete"
if [[ "$inserted" == "true" && -n "$final_transcript" ]]; then
  success="true"
  target_capture_success="true"
  reason="trace_inserted"
elif [[ "$paste_command_posted" == "true" && -n "$final_transcript" ]]; then
  reason="paste_command_posted_without_insert_confirmation"
elif [[ -n "$final_transcript" ]]; then
  reason="final_transcript_without_insert_confirmation"
fi

if [[ -z "$JSON_OUTPUT_PATH" ]]; then
  mkdir -p "$DIAGNOSTICS_DIR"
  stamp="$(date -u '+%Y-%m-%dT%H-%M-%SZ')"
  JSON_OUTPUT_PATH="$DIAGNOSTICS_DIR/real-field-smoke-$stamp.json"
else
  mkdir -p "$(dirname "$JSON_OUTPUT_PATH")"
fi

tmp_plist="$(mktemp "${TMPDIR:-/tmp}/presstalk-real-field-smoke.XXXXXX")"
trap 'rm -f "$tmp_plist"' EXIT
plutil -create xml1 "$tmp_plist" >/dev/null

plist_insert_string "$tmp_plist" "schemaVersion" "1"
plist_insert_string "$tmp_plist" "generatedAt" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
plist_insert_string "$tmp_plist" "source" "trace_log"
plist_insert_string "$tmp_plist" "traceLog" "$TRACE_LOG"
plist_insert_string "$tmp_plist" "statusJson" "$STATUS_JSON"
plist_insert_bool "$tmp_plist" "success" "$success"
plist_insert_string "$tmp_plist" "reason" "$reason"
plist_insert_bool "$tmp_plist" "targetCaptureSuccess" "$target_capture_success"
plist_insert_string "$tmp_plist" "userReport" "$USER_REPORT"

plutil -insert "runtime" -dictionary "$tmp_plist" >/dev/null
plist_insert_string "$tmp_plist" "runtime.triggerKey" "$(status_value runtime.triggerKey)"
plist_insert_string "$tmp_plist" "runtime.triggerPath" "$(status_value status.triggerPath)"
plist_insert_string "$tmp_plist" "runtime.asrBackend" "$(status_value runtime.asrBackend)"
plist_insert_string "$tmp_plist" "runtime.streamingASRBackend" "$(status_value runtime.streamingASRBackend)"
plist_insert_string "$tmp_plist" "runtime.asrMode" "$(status_value runtime.asrMode)"
plist_insert_string "$tmp_plist" "runtime.realtimePartialTranscriptionEnabled" "$(status_value runtime.realtimePartialTranscriptionEnabled)"

plutil -insert "observed" -dictionary "$tmp_plist" >/dev/null
plist_insert_string "$tmp_plist" "observed.appStartedAt" "$app_started_at"
plist_insert_string "$tmp_plist" "observed.pressedAt" "$pressed_at"
plist_insert_string "$tmp_plist" "observed.releasedAt" "$released_at"
plist_insert_string "$tmp_plist" "observed.insertedAt" "$inserted_at"
plist_insert_number_or_string "$tmp_plist" "observed.heldMs" "$held_ms"
plist_insert_number_or_string "$tmp_plist" "observed.releaseToInsertMs" "$release_to_insert_ms"
plist_insert_number_or_string "$tmp_plist" "observed.audioDurationSeconds" "$audio_duration_seconds"
plist_insert_string "$tmp_plist" "observed.streamingASRBackend" "$streaming_asr_backend_observed"
plist_insert_number_or_string "$tmp_plist" "observed.partialUpdateCount" "$partial_update_count"
plist_insert_string "$tmp_plist" "observed.lastPartialTranscript" "$last_partial_transcript"
plist_insert_bool "$tmp_plist" "observed.captureFrozen" "$capture_frozen"
plist_insert_number_or_string "$tmp_plist" "observed.parakeetInferenceSeconds" "$parakeet_inference_seconds"
plist_insert_number_or_string "$tmp_plist" "observed.parakeetConfidence" "$parakeet_confidence"
plist_insert_string "$tmp_plist" "observed.parakeetTranscript" "$parakeet_transcript"
plist_insert_bool "$tmp_plist" "observed.whisperFallbackRequested" "$whisper_fallback_requested"
plist_insert_string "$tmp_plist" "observed.whisperTranscript" "$whisper_transcript"
plist_insert_string "$tmp_plist" "observed.finalizer" "$finalizer"
plist_insert_string "$tmp_plist" "observed.finalTranscript" "$final_transcript"
plist_insert_bool "$tmp_plist" "observed.pasteCommandPosted" "$paste_command_posted"
plist_insert_bool "$tmp_plist" "observed.inserted" "$inserted"
plist_insert_string "$tmp_plist" "observed.insertionMethod" "$insertion_method"

plutil -convert json -r -o "$JSON_OUTPUT_PATH" "$tmp_plist"

cat <<EOF
PressTalk real-field smoke collected

JSON: $JSON_OUTPUT_PATH
Success: $success
Reason: $reason
Trigger: $(status_value runtime.triggerKey)
Runtime streaming ASR backend: $(status_value runtime.streamingASRBackend)
Observed streaming ASR backend: ${streaming_asr_backend_observed:-unknown}
Partial updates: ${partial_update_count:-unknown}
Finalizer: ${finalizer:-unknown}
ReleaseToInsertMs: ${release_to_insert_ms:-unknown}
InsertionMethod: ${insertion_method:-unknown}
FinalTranscript: ${final_transcript:-unknown}
EOF

if [[ "$success" != "true" ]]; then
  exit 1
fi
