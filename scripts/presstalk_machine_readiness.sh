#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${PRESSTALK_APP_BUNDLE:-$HOME/Applications/PressTalk.app}"
STATUS_JSON="${PRESSTALK_STATUS_JSON:-$HOME/Library/Application Support/JarvisTap/runtime-status.json}"
DIAGNOSTICS_DIR="${PRESSTALK_DIAGNOSTICS_DIR:-$HOME/Library/Application Support/JarvisTap/Diagnostics}"
OUTPUT_FORMAT="text"
JSON_OUTPUT_PATH=""

usage() {
  cat <<'EOF'
Usage: presstalk-machine-readiness.sh [--json] [--json-output PATH]

Reports whether this Mac is eligible for PressTalk physical STT smoke, whether
the running app is ready, and what the next action is. It is read-only: it does
not open System Settings, bootstrap PressTalk, or run signing repair.

Options:
  --json              Write only machine-readable JSON to stdout.
  --json-output PATH  Also write the machine-readable JSON report to PATH.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_FORMAT="json"
      ;;
    --json-output)
      shift
      if [[ $# -eq 0 || -z "$1" ]]; then
        echo "Missing value for --json-output" >&2
        exit 2
      fi
      JSON_OUTPUT_PATH="$1"
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
  shift
done

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

accessibility_handoff_command_path() {
  printf '%s\n' "${PRESSTALK_ACCESSIBILITY_DESKTOP_COMMAND_PATH:-$HOME/Desktop/Grant PressTalk Accessibility.command}"
}

accessibility_tcc_auth_value() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    return 0
  fi

  local client db value
  client="${bundle_id:-com.am.presstalk}"
  for db in \
    "${PRESSTALK_SYSTEM_TCC_DB:-/Library/Application Support/com.apple.TCC/TCC.db}" \
    "${PRESSTALK_USER_TCC_DB:-$HOME/Library/Application Support/com.apple.TCC/TCC.db}"; do
    [[ -r "$db" ]] || continue
    value="$(sqlite3 "$db" "
      SELECT auth_value
      FROM access
      WHERE service='kTCCServiceAccessibility'
        AND client='$client'
      ORDER BY last_modified DESC
      LIMIT 1;
    " 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
}

accessibility_tcc_summary() {
  case "${accessibility_tcc_auth_value:-}" in
    2) printf 'granted' ;;
    0) printf 'listed_disabled' ;;
    "") printf 'missing_or_unreadable' ;;
    *) printf 'present_non_granted' ;;
  esac
}

recognized_disabled_next_action() {
  local command_path
  command_path="$(accessibility_handoff_command_path)"
  if [[ -x "$command_path" ]]; then
    if [[ "$(accessibility_tcc_summary)" == "listed_disabled" ]]; then
      printf 'Input method is recognized but still disabled; do not rerun signing repair or privacy panes. PressTalk is already listed in Accessibility but disabled; from the logged-in desktop, double-click %s, turn on the existing PressTalk entry only, then let it run the insertion probe.' "$command_path"
    else
      printf 'Input method is recognized but still disabled; do not rerun signing repair or privacy panes. From the logged-in desktop, double-click %s to grant only PressTalk Accessibility and run the insertion probe.' "$command_path"
    fi
  elif [[ -x "$APP_BUNDLE/Contents/Resources/presstalk-accessibility-handoff.sh" ]]; then
    printf 'Input method is recognized but still disabled; do not rerun signing repair or privacy panes. Write the desktop Accessibility handoff with: /bin/bash "%s/Contents/Resources/presstalk-accessibility-handoff.sh" --write-desktop-command' "$APP_BUNDLE"
  else
    printf 'Input method is recognized but still disabled; do not rerun signing repair or privacy panes. Inspect TIS enable-no-effect or use the Accessibility insertion path.'
  fi
}

print_field() {
  local label="$1"
  local value="$2"
  echo "$label: ${value:-unknown}"
}

bundle_signature_value() {
  local path="$1"
  local key="$2"
  if [[ -d "$path" ]]; then
    codesign -dv --verbose=4 "$path" 2>&1 |
      awk -F= -v key="$key" '$1 == key { value = $2 } END { if (value != "") print value }'
  fi
}

bundle_identifier() {
  local path="$1"
  if [[ -f "$path/Contents/Info.plist" ]]; then
    /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$path/Contents/Info.plist" 2>/dev/null || true
  fi
}

audio_input_devices() {
  if ! command -v system_profiler >/dev/null 2>&1; then
    return 0
  fi

  system_profiler SPAudioDataType 2>/dev/null |
    awk '
      /^[[:space:]]{4}[^:][^:]*:$/ {
        device = $0
        sub(/^[[:space:]]+/, "", device)
        sub(/:$/, "", device)
      }
      /Input Channels:/ {
        channels = $0
        sub(/^.*Input Channels:[[:space:]]*/, "", channels)
        if ((channels + 0) > 0 && device != "") {
          print device
        }
      }
    ' |
    sort -u
}

plist_insert_string() {
  local plist="$1"
  local key="$2"
  local value="${3:-}"
  plutil -insert "$key" -string "${value:-unknown}" "$plist" >/dev/null
}

plist_insert_bool_or_string() {
  local plist="$1"
  local key="$2"
  local value="${3:-}"
  case "$value" in
    true|false)
      plutil -insert "$key" -bool "$value" "$plist" >/dev/null
      ;;
    *)
      plutil -insert "$key" -string "${value:-unknown}" "$plist" >/dev/null
      ;;
  esac
}

plist_insert_array() {
  local plist="$1"
  local key="$2"
  shift 2
  plutil -insert "$key" -array "$plist" >/dev/null
  local value
  for value in "$@"; do
    plutil -insert "$key" -string "$value" -append "$plist" >/dev/null
  done
}

hostname_value="$(hostname 2>/dev/null || true)"
local_hostname="$(scutil --get LocalHostName 2>/dev/null || true)"
computer_name="$(scutil --get ComputerName 2>/dev/null || true)"
arch="$(uname -m 2>/dev/null || true)"
os_version="$(sw_vers -productVersion 2>/dev/null || true)"
build_version="$(sw_vers -buildVersion 2>/dev/null || true)"
hardware_model="$(sysctl -n hw.model 2>/dev/null || true)"
cpu_brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
apple_silicon="$(if [[ "$arch" == "arm64" ]]; then echo "true"; else echo "false"; fi)"

input_devices=()
while IFS= read -r input_device; do
  [[ -z "$input_device" ]] && continue
  input_devices+=("$input_device")
done < <(audio_input_devices)

microphone_detected="unknown"
audio_reason=""
if command -v system_profiler >/dev/null 2>&1; then
  if [[ "${#input_devices[@]}" -gt 0 ]]; then
    microphone_detected="true"
  else
    microphone_detected="false"
    audio_reason="no audio device with input channels was reported"
  fi
else
  audio_reason="system_profiler unavailable"
fi

press_talk_installed="false"
bundle_id=""
signature_identifier=""
signature_cdhash=""
signature_authority=""
if [[ -d "$APP_BUNDLE" ]]; then
  press_talk_installed="true"
  bundle_id="$(bundle_identifier "$APP_BUNDLE")"
  signature_identifier="$(bundle_signature_value "$APP_BUNDLE" Identifier)"
  signature_cdhash="$(bundle_signature_value "$APP_BUNDLE" CDHash)"
  signature_authority="$(bundle_signature_value "$APP_BUNDLE" Authority)"
fi

runtime_status_available="false"
speech_model=""
input_pipeline_ready=""
input_listener=""
trigger_path=""
microphone_authorization=""
input_monitoring_effective=""
active_field_ready=""
active_field_status=""
input_method_fallback=""
accessibility_status=""
ad_hoc_signed=""
accessibility_tcc_auth_value=""
if [[ -f "$STATUS_JSON" ]]; then
  runtime_status_available="true"
  speech_model="$(status_value status.speechModel)"
  input_pipeline_ready="$(status_value runtime.inputPipelineReady)"
  input_listener="$(status_value runtime.inputListener)"
  trigger_path="$(status_value status.triggerPath)"
  microphone_authorization="$(status_value permissions.microphoneAuthorizationStatus)"
  input_monitoring_effective="$(status_value permissions.inputMonitoringEffective)"
  active_field_ready="$(status_value runtime.activeFieldInsertionReady)"
  active_field_status="$(status_value runtime.activeFieldInsertionStatus)"
  input_method_fallback="$(status_value permissions.inputMethodFallbackStatus)"
  accessibility_status="$(status_value permissions.accessibilityStatus)"
  ad_hoc_signed="$(status_value status.adHocSigned)"
fi
accessibility_tcc_auth_value="$(accessibility_tcc_auth_value)"

latest_probe_json="$(latest_diagnostic_file 'production-insertion-probe-*.json')"
probe_generated_at=""
probe_success=""
probe_target_capture_success=""
probe_trace_production_method=""
if [[ -n "$latest_probe_json" ]]; then
  probe_generated_at="$(json_file_value "$latest_probe_json" generatedAt)"
  probe_success="$(json_file_value "$latest_probe_json" success)"
  probe_target_capture_success="$(json_file_value "$latest_probe_json" targetCaptureSuccess)"
  probe_trace_production_method="$(json_file_value "$latest_probe_json" traceProductionMethod)"
fi

latest_manual_json="$(latest_diagnostic_file 'manual-trigger-smoke-*.json')"
manual_generated_at=""
manual_success=""
manual_reason=""
manual_expected_trigger_key=""
manual_expected_trigger_proof=""
manual_target_capture_success=""
manual_trace_registered_hotkey_observed=""
manual_trace_final_transcript=""
if [[ -n "$latest_manual_json" ]]; then
  manual_generated_at="$(json_file_value "$latest_manual_json" generatedAt)"
  manual_success="$(json_file_value "$latest_manual_json" success)"
  manual_reason="$(json_file_value "$latest_manual_json" reason)"
  manual_expected_trigger_key="$(json_file_value "$latest_manual_json" expectedTriggerKey)"
  manual_expected_trigger_proof="$(json_file_value "$latest_manual_json" expectedTriggerProof)"
  manual_target_capture_success="$(json_file_value "$latest_manual_json" targetCaptureSuccess)"
  manual_trace_registered_hotkey_observed="$(json_file_value "$latest_manual_json" traceRegisteredHotKeyObserved)"
  manual_trace_final_transcript="$(json_file_value "$latest_manual_json" traceFinalTranscript)"
fi

install_smoke_eligible="false"
if [[ "$apple_silicon" == "true" && "$microphone_detected" != "false" ]]; then
  install_smoke_eligible="true"
fi

physical_stt_smoke_ready="false"
if [[ "$runtime_status_available" == "true" ]] &&
   [[ "$apple_silicon" == "true" ]] &&
   [[ "$microphone_detected" == "true" ]] &&
   [[ "$input_pipeline_ready" == "true" ]] &&
   [[ "$speech_model" == "Ready" ]] &&
   [[ "$microphone_authorization" == "authorized" ]]; then
  physical_stt_smoke_ready="true"
fi

active_field_smoke_ready="false"
if [[ "$physical_stt_smoke_ready" == "true" && "$active_field_ready" == "true" ]]; then
  active_field_smoke_ready="true"
fi

if [[ "$apple_silicon" != "true" ]]; then
  next_action="Not eligible: this is not an arm64 Apple Silicon Mac."
elif [[ "$microphone_detected" == "false" ]]; then
  next_action="Attach or select an input microphone before running physical STT smoke."
elif [[ "$press_talk_installed" != "true" ]]; then
  next_action="Install the current PressTalk prerelease, then rerun this helper."
elif [[ "$runtime_status_available" != "true" ]]; then
  next_action="Run PressTalk bootstrap/startup, wait for runtime-status.json, then rerun this helper."
elif [[ "$input_pipeline_ready" != "true" || "$speech_model" != "Ready" ]]; then
  next_action="Speech pipeline is not ready; collect smoke status before running a physical dictation smoke."
elif [[ "$active_field_ready" != "true" ]]; then
  if [[ "$active_field_status" == "needs_signing_repair" ||
        ( "$input_method_fallback" == "recognized_disabled" && "$ad_hoc_signed" == "true" ) ]]; then
    next_action="Run logged-in desktop Repair Signing; do not reopen privacy panes for this state."
  elif [[ "$input_method_fallback" == "recognized_disabled" ]]; then
    next_action="$(recognized_disabled_next_action)"
  else
    next_action="Active-field insertion is not ready; collect smoke status and inspect the insertion blocker."
  fi
else
  if [[ -n "$trigger_path" && "$trigger_path" != "unknown" ]]; then
    next_action="Ready for physical dictation smoke using configured trigger: $trigger_path."
  else
    next_action="Ready for physical dictation smoke with the configured trigger."
  fi
fi

print_text_report() {
  echo "PressTalk machine readiness"
  echo

  print_field "Host" "$hostname_value"
  print_field "LocalHostName" "$local_hostname"
  print_field "ComputerName" "$computer_name"
  print_field "Architecture" "$arch"
  print_field "AppleSilicon" "$apple_silicon"
  print_field "macOS" "${os_version}${build_version:+ ($build_version)}"
  print_field "HardwareModel" "$hardware_model"
  print_field "CPU" "$cpu_brand"

  echo
  echo "Audio input hardware"
  if ! command -v system_profiler >/dev/null 2>&1; then
    echo "MicrophoneHardwareDetected: unknown"
    echo "Reason: $audio_reason"
  elif [[ "$microphone_detected" == "true" ]]; then
    echo "MicrophoneHardwareDetected: true"
    printf 'InputDevices:\n'
    printf -- '- %s\n' "${input_devices[@]}"
  else
    echo "MicrophoneHardwareDetected: false"
    echo "Reason: $audio_reason"
  fi

  echo
  echo "PressTalk install"
  print_field "AppBundle" "$APP_BUNDLE"
  if [[ "$press_talk_installed" == "true" ]]; then
    echo "PressTalkInstalled: true"
    print_field "BundleIdentifier" "$bundle_id"
    print_field "CodeSignatureIdentifier" "$signature_identifier"
    print_field "CodeSignatureCDHash" "$signature_cdhash"
    print_field "CodeSignatureAuthority" "$signature_authority"
  else
    echo "PressTalkInstalled: false"
  fi

  echo
  echo "Runtime status"
  print_field "RuntimeStatus" "$STATUS_JSON"
  if [[ "$runtime_status_available" == "true" ]]; then
    echo "RuntimeStatusAvailable: true"
    print_field "SpeechModel" "$speech_model"
    print_field "InputPipelineReady" "$input_pipeline_ready"
    print_field "InputListener" "$input_listener"
    print_field "TriggerPath" "$trigger_path"
    print_field "MicrophoneAuthorizationStatus" "$microphone_authorization"
    print_field "InputMonitoringEffective" "$input_monitoring_effective"
    print_field "ActiveFieldInsertionReady" "$active_field_ready"
    print_field "ActiveFieldInsertionStatus" "$active_field_status"
    print_field "InputMethodFallbackStatus" "$input_method_fallback"
    print_field "AccessibilityStatus" "$accessibility_status"
    print_field "AccessibilityTCCAuthValue" "$accessibility_tcc_auth_value"
    print_field "AdHocSigned" "$ad_hoc_signed"
  else
    echo "RuntimeStatusAvailable: false"
  fi

  echo
  echo "Latest production insertion probe"
  if [[ -n "$latest_probe_json" ]]; then
    print_field "ProbePath" "$latest_probe_json"
    print_field "ProbeGeneratedAt" "$probe_generated_at"
    print_field "ProbeSuccess" "$probe_success"
    print_field "ProbeTargetCaptureSuccess" "$probe_target_capture_success"
    print_field "ProbeTraceProductionMethod" "$probe_trace_production_method"
  else
    echo "ProbePath: none found"
  fi

  echo
  echo "Latest manual physical trigger smoke"
  if [[ -n "$latest_manual_json" ]]; then
    print_field "ManualSmokePath" "$latest_manual_json"
    print_field "ManualSmokeGeneratedAt" "$manual_generated_at"
    print_field "ManualSmokeSuccess" "$manual_success"
    print_field "ManualSmokeReason" "$manual_reason"
    print_field "ManualSmokeExpectedTriggerKey" "$manual_expected_trigger_key"
    print_field "ManualSmokeExpectedTriggerProof" "$manual_expected_trigger_proof"
    print_field "ManualSmokeTargetCaptureSuccess" "$manual_target_capture_success"
    print_field "ManualSmokeTraceRegisteredHotKeyObserved" "$manual_trace_registered_hotkey_observed"
    print_field "ManualSmokeTraceFinalTranscript" "$manual_trace_final_transcript"
  else
    echo "ManualSmokePath: none found"
  fi

  echo
  echo "Eligibility"
  print_field "InstallSmokeEligible" "$install_smoke_eligible"
  print_field "PhysicalSTTSmokeReady" "$physical_stt_smoke_ready"
  print_field "ActiveFieldSmokeReady" "$active_field_smoke_ready"

  echo
  echo "Next action"
  echo "$next_action"
}

write_json_report() {
  local output_path="$1"
  local tmp_plist
  tmp_plist="$(mktemp "${TMPDIR:-/tmp}/presstalk-readiness.XXXXXX")"
  trap 'rm -f "$tmp_plist"' RETURN

  plutil -create xml1 "$tmp_plist" >/dev/null
  plist_insert_string "$tmp_plist" "schemaVersion" "1"
  plist_insert_string "$tmp_plist" "generatedAt" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  plist_insert_string "$tmp_plist" "appBundle" "$APP_BUNDLE"
  plist_insert_string "$tmp_plist" "statusJson" "$STATUS_JSON"
  plist_insert_string "$tmp_plist" "diagnosticsDir" "$DIAGNOSTICS_DIR"

  plutil -insert "machine" -dictionary "$tmp_plist" >/dev/null
  plist_insert_string "$tmp_plist" "machine.host" "$hostname_value"
  plist_insert_string "$tmp_plist" "machine.localHostName" "$local_hostname"
  plist_insert_string "$tmp_plist" "machine.computerName" "$computer_name"
  plist_insert_string "$tmp_plist" "machine.architecture" "$arch"
  plist_insert_bool_or_string "$tmp_plist" "machine.appleSilicon" "$apple_silicon"
  plist_insert_string "$tmp_plist" "machine.macOSVersion" "$os_version"
  plist_insert_string "$tmp_plist" "machine.macOSBuild" "$build_version"
  plist_insert_string "$tmp_plist" "machine.hardwareModel" "$hardware_model"
  plist_insert_string "$tmp_plist" "machine.cpu" "$cpu_brand"

  plutil -insert "audio" -dictionary "$tmp_plist" >/dev/null
  plist_insert_bool_or_string "$tmp_plist" "audio.microphoneHardwareDetected" "$microphone_detected"
  plist_insert_string "$tmp_plist" "audio.reason" "$audio_reason"
  plist_insert_array "$tmp_plist" "audio.inputDevices" "${input_devices[@]}"

  plutil -insert "pressTalk" -dictionary "$tmp_plist" >/dev/null
  plist_insert_bool_or_string "$tmp_plist" "pressTalk.installed" "$press_talk_installed"
  plist_insert_string "$tmp_plist" "pressTalk.bundleIdentifier" "$bundle_id"
  plist_insert_string "$tmp_plist" "pressTalk.codeSignatureIdentifier" "$signature_identifier"
  plist_insert_string "$tmp_plist" "pressTalk.codeSignatureCDHash" "$signature_cdhash"
  plist_insert_string "$tmp_plist" "pressTalk.codeSignatureAuthority" "$signature_authority"

  plutil -insert "runtime" -dictionary "$tmp_plist" >/dev/null
  plist_insert_bool_or_string "$tmp_plist" "runtime.statusAvailable" "$runtime_status_available"
  plist_insert_string "$tmp_plist" "runtime.speechModel" "$speech_model"
  plist_insert_bool_or_string "$tmp_plist" "runtime.inputPipelineReady" "$input_pipeline_ready"
  plist_insert_string "$tmp_plist" "runtime.inputListener" "$input_listener"
  plist_insert_string "$tmp_plist" "runtime.triggerPath" "$trigger_path"
  plist_insert_string "$tmp_plist" "runtime.microphoneAuthorizationStatus" "$microphone_authorization"
  plist_insert_bool_or_string "$tmp_plist" "runtime.inputMonitoringEffective" "$input_monitoring_effective"
  plist_insert_bool_or_string "$tmp_plist" "runtime.activeFieldInsertionReady" "$active_field_ready"
  plist_insert_string "$tmp_plist" "runtime.activeFieldInsertionStatus" "$active_field_status"
  plist_insert_string "$tmp_plist" "runtime.inputMethodFallbackStatus" "$input_method_fallback"
  plist_insert_string "$tmp_plist" "runtime.accessibilityStatus" "$accessibility_status"
  plist_insert_string "$tmp_plist" "runtime.accessibilityTCCAuthValue" "$accessibility_tcc_auth_value"
  plist_insert_bool_or_string "$tmp_plist" "runtime.adHocSigned" "$ad_hoc_signed"

  plutil -insert "latestProductionInsertionProbe" -dictionary "$tmp_plist" >/dev/null
  plist_insert_string "$tmp_plist" "latestProductionInsertionProbe.path" "${latest_probe_json:-none}"
  plist_insert_string "$tmp_plist" "latestProductionInsertionProbe.generatedAt" "$probe_generated_at"
  plist_insert_bool_or_string "$tmp_plist" "latestProductionInsertionProbe.success" "$probe_success"
  plist_insert_bool_or_string "$tmp_plist" "latestProductionInsertionProbe.targetCaptureSuccess" "$probe_target_capture_success"
  plist_insert_string "$tmp_plist" "latestProductionInsertionProbe.traceProductionMethod" "$probe_trace_production_method"

  plutil -insert "latestManualPhysicalTriggerSmoke" -dictionary "$tmp_plist" >/dev/null
  plist_insert_string "$tmp_plist" "latestManualPhysicalTriggerSmoke.path" "${latest_manual_json:-none}"
  plist_insert_string "$tmp_plist" "latestManualPhysicalTriggerSmoke.generatedAt" "$manual_generated_at"
  plist_insert_bool_or_string "$tmp_plist" "latestManualPhysicalTriggerSmoke.success" "$manual_success"
  plist_insert_string "$tmp_plist" "latestManualPhysicalTriggerSmoke.reason" "$manual_reason"
  plist_insert_string "$tmp_plist" "latestManualPhysicalTriggerSmoke.expectedTriggerKey" "$manual_expected_trigger_key"
  plist_insert_bool_or_string "$tmp_plist" "latestManualPhysicalTriggerSmoke.expectedTriggerProof" "$manual_expected_trigger_proof"
  plist_insert_bool_or_string "$tmp_plist" "latestManualPhysicalTriggerSmoke.targetCaptureSuccess" "$manual_target_capture_success"
  plist_insert_bool_or_string "$tmp_plist" "latestManualPhysicalTriggerSmoke.traceRegisteredHotKeyObserved" "$manual_trace_registered_hotkey_observed"
  plist_insert_string "$tmp_plist" "latestManualPhysicalTriggerSmoke.traceFinalTranscript" "$manual_trace_final_transcript"

  plutil -insert "eligibility" -dictionary "$tmp_plist" >/dev/null
  plist_insert_bool_or_string "$tmp_plist" "eligibility.installSmokeEligible" "$install_smoke_eligible"
  plist_insert_bool_or_string "$tmp_plist" "eligibility.physicalSTTSmokeReady" "$physical_stt_smoke_ready"
  plist_insert_bool_or_string "$tmp_plist" "eligibility.activeFieldSmokeReady" "$active_field_smoke_ready"
  plist_insert_string "$tmp_plist" "nextAction" "$next_action"

  plutil -convert json -r -o "$output_path" "$tmp_plist"
  rm -f "$tmp_plist"
  trap - RETURN
}

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  write_json_report "-"
else
  print_text_report
fi

if [[ -n "$JSON_OUTPUT_PATH" ]]; then
  write_json_report "$JSON_OUTPUT_PATH"
  if [[ "$OUTPUT_FORMAT" != "json" ]]; then
    echo
    echo "ReadinessJSON: $JSON_OUTPUT_PATH"
  fi
fi
