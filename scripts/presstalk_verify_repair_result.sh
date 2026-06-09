#!/usr/bin/env bash
set -euo pipefail

STATUS_JSON="${PRESSTALK_STATUS_JSON:-$HOME/Library/Application Support/JarvisTap/runtime-status.json}"
DIAGNOSTICS_DIR="${PRESSTALK_DIAGNOSTICS_DIR:-$HOME/Library/Application Support/JarvisTap/Diagnostics}"

json_file_value() {
  local file="$1"
  local key_path="$2"
  if [[ -f "$file" ]]; then
    plutil -extract "$key_path" raw -o - "$file" 2>/dev/null || true
  fi
}

status_value() {
  local key_path="$1"
  json_file_value "$STATUS_JSON" "$key_path"
}

latest_diagnostic_file() {
  local name_pattern="$1"
  if [[ ! -d "$DIAGNOSTICS_DIR" ]]; then
    return 0
  fi

  local matches=()
  while IFS= read -r -d '' file; do
    matches+=("$file")
  done < <(find "$DIAGNOSTICS_DIR" -maxdepth 1 -type f -name "$name_pattern" -print0 2>/dev/null)

  if [[ "${#matches[@]}" -eq 0 ]]; then
    return 0
  fi

  ls -t "${matches[@]}" 2>/dev/null | head -n 1
}

print_field() {
  local label="$1"
  local value="$2"
  echo "$label: ${value:-unknown}"
}

echo "PressTalk repair result verifier"
echo "Runtime status: $STATUS_JSON"
echo "Diagnostics directory: $DIAGNOSTICS_DIR"

if [[ ! -f "$STATUS_JSON" ]]; then
  echo "Result: not proven"
  echo "Reason: runtime status file is missing"
  exit 2
fi

ad_hoc_signed="$(status_value status.adHocSigned)"
code_signature_authority="$(status_value status.codeSignatureAuthority)"
input_method_fallback="$(status_value permissions.inputMethodFallbackStatus)"
accessibility_status="$(status_value permissions.accessibilityStatus)"
speech_model="$(status_value status.speechModel)"
input_listener="$(status_value runtime.inputListener)"
active_field_insertion_ready="$(status_value runtime.activeFieldInsertionReady)"
active_field_insertion_status="$(status_value runtime.activeFieldInsertionStatus)"
microphone_authorization="$(status_value permissions.microphoneAuthorizationStatus)"
input_monitoring_effective="$(status_value permissions.inputMonitoringEffective)"

print_field "adHocSigned" "$ad_hoc_signed"
print_field "codeSignatureAuthority" "$code_signature_authority"
print_field "inputMethodFallbackStatus" "$input_method_fallback"
print_field "accessibilityStatus" "$accessibility_status"
print_field "speechModel" "$speech_model"
print_field "inputListener" "$input_listener"
print_field "activeFieldInsertionReady" "$active_field_insertion_ready"
print_field "activeFieldInsertionStatus" "$active_field_insertion_status"
print_field "microphoneAuthorizationStatus" "$microphone_authorization"
print_field "inputMonitoringEffective" "$input_monitoring_effective"

latest_repair_log="$(latest_diagnostic_file 'presstalk-signing-repair-*.log')"
if [[ -n "$latest_repair_log" ]]; then
  echo "Latest signing repair log: $latest_repair_log"
  latest_repair_pid_file="${latest_repair_log%.log}.pid"
  if [[ -f "$latest_repair_pid_file" ]]; then
    latest_repair_pid="$(tr -dc '0-9' <"$latest_repair_pid_file" 2>/dev/null || true)"
    if [[ -n "$latest_repair_pid" ]] && kill -0 "$latest_repair_pid" >/dev/null 2>&1; then
      echo "Latest signing repair process: running pid=$latest_repair_pid"
      echo "Result: waiting"
      echo "Reason: signing repair helper is still running"
      exit 2
    elif [[ -n "$latest_repair_pid" ]]; then
      echo "Latest signing repair process: not running pid=$latest_repair_pid"
    else
      echo "Latest signing repair process: PID file empty"
    fi
  fi
else
  echo "Latest signing repair log: none found"
fi

latest_probe_json="$(latest_diagnostic_file 'production-insertion-probe-*.json')"
if [[ -z "$latest_probe_json" ]]; then
  echo "Result: not proven"
  echo "Reason: no production insertion probe JSON found"
  exit 2
fi

echo "Latest production insertion probe: $latest_probe_json"
probe_generated_at="$(json_file_value "$latest_probe_json" generatedAt)"
probe_success="$(json_file_value "$latest_probe_json" success)"
probe_reason="$(json_file_value "$latest_probe_json" reason)"
probe_target_capture_success="$(json_file_value "$latest_probe_json" targetCaptureSuccess)"
probe_failure_hint="$(json_file_value "$latest_probe_json" targetCaptureFailureHint)"
probe_trace_method="$(json_file_value "$latest_probe_json" traceProductionMethod)"
probe_paste_command_posted="$(json_file_value "$latest_probe_json" tracePasteCommandPosted)"
probe_trace_copy_fallback="$(json_file_value "$latest_probe_json" traceCopyFallback)"
probe_enable_no_effect="$(json_file_value "$latest_probe_json" traceInputMethodEnableNoEffect)"

print_field "probe.generatedAt" "$probe_generated_at"
print_field "probe.success" "$probe_success"
print_field "probe.reason" "$probe_reason"
print_field "probe.targetCaptureSuccess" "$probe_target_capture_success"
print_field "probe.targetCaptureFailureHint" "$probe_failure_hint"
print_field "probe.traceProductionMethod" "$probe_trace_method"
print_field "probe.tracePasteCommandPosted" "$probe_paste_command_posted"
print_field "probe.traceCopyFallback" "$probe_trace_copy_fallback"
print_field "probe.traceInputMethodEnableNoEffect" "$probe_enable_no_effect"

if [[ "$active_field_insertion_ready" != "true" ]]; then
  echo "Result: not proven"
  if [[ "$active_field_insertion_status" == "needs_signing_repair" ||
        ( "$input_method_fallback" == "recognized_disabled" && "$ad_hoc_signed" == "true" ) ]]; then
    echo "Reason: active-field insertion needs signing repair"
  elif [[ "$input_method_fallback" == "recognized_disabled" ]]; then
    echo "Reason: active-field insertion is blocked because the PressTalk input method is recognized but disabled"
  elif [[ "$input_method_fallback" == "client_unavailable" ]]; then
    echo "Reason: active-field insertion is blocked because the PressTalk input method could not attach to the focused text field"
  elif [[ "$input_method_fallback" == "ack_timeout" ]]; then
    echo "Reason: active-field insertion is blocked because the PressTalk input method did not acknowledge insertion"
  else
    echo "Reason: active-field insertion is not ready"
  fi
  exit 1
fi

if [[ "$probe_success" != "true" || "$probe_target_capture_success" != "true" ]]; then
  echo "Result: not proven"
  echo "Reason: latest production insertion probe did not capture inserted text"
  exit 1
fi

if [[ "$probe_trace_copy_fallback" == "true" || "$probe_enable_no_effect" == "true" ]]; then
  echo "Result: not proven"
  echo "Reason: latest probe used fallback or still saw input-method enable no-effect"
  exit 1
fi

case "$probe_trace_method" in
  input_method_notification)
    if [[ "$input_method_fallback" != "ready" ]]; then
      echo "Result: not proven"
      echo "Reason: latest probe used input method, but current input method fallback is not ready"
      exit 1
    fi
    ;;
  ax_selected_text|ax_value_range)
    if [[ "$accessibility_status" != "ax_trusted" ]]; then
      echo "Result: not proven"
      echo "Reason: latest probe used Accessibility, but current Accessibility status is not trusted"
      exit 1
    fi
    ;;
  *)
    if [[ "$probe_paste_command_posted" == "true" && "$accessibility_status" == "ax_trusted" ]]; then
      :
    else
      echo "Result: not proven"
      echo "Reason: latest probe did not prove a current active-field insertion path"
      exit 1
    fi
    ;;
esac

echo "Result: proven"
echo "Reason: runtime insertion path is ready and latest production insertion probe inserted into the focused target"
exit 0
