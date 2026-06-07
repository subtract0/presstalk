#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${PRESSTALK_APP_BUNDLE:-$HOME/Applications/PressTalk.app}"
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

echo "PressTalk machine readiness"
echo

hostname_value="$(hostname 2>/dev/null || true)"
local_hostname="$(scutil --get LocalHostName 2>/dev/null || true)"
computer_name="$(scutil --get ComputerName 2>/dev/null || true)"
arch="$(uname -m 2>/dev/null || true)"
os_version="$(sw_vers -productVersion 2>/dev/null || true)"
build_version="$(sw_vers -buildVersion 2>/dev/null || true)"
hardware_model="$(sysctl -n hw.model 2>/dev/null || true)"
cpu_brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
apple_silicon="$(if [[ "$arch" == "arm64" ]]; then echo "true"; else echo "false"; fi)"

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
input_devices=()
while IFS= read -r input_device; do
  [[ -z "$input_device" ]] && continue
  input_devices+=("$input_device")
done < <(audio_input_devices)
if ! command -v system_profiler >/dev/null 2>&1; then
  echo "MicrophoneHardwareDetected: unknown"
  echo "Reason: system_profiler unavailable"
elif [[ "${#input_devices[@]}" -gt 0 ]]; then
  echo "MicrophoneHardwareDetected: true"
  printf 'InputDevices:\n'
  printf -- '- %s\n' "${input_devices[@]}"
else
  echo "MicrophoneHardwareDetected: false"
  echo "Reason: no audio device with input channels was reported"
fi

echo
echo "PressTalk install"
print_field "AppBundle" "$APP_BUNDLE"
if [[ -d "$APP_BUNDLE" ]]; then
  echo "PressTalkInstalled: true"
  print_field "BundleIdentifier" "$(bundle_identifier "$APP_BUNDLE")"
  print_field "CodeSignatureIdentifier" "$(bundle_signature_value "$APP_BUNDLE" Identifier)"
  print_field "CodeSignatureCDHash" "$(bundle_signature_value "$APP_BUNDLE" CDHash)"
  print_field "CodeSignatureAuthority" "$(bundle_signature_value "$APP_BUNDLE" Authority)"
else
  echo "PressTalkInstalled: false"
fi

echo
echo "Runtime status"
print_field "RuntimeStatus" "$STATUS_JSON"
if [[ -f "$STATUS_JSON" ]]; then
  echo "RuntimeStatusAvailable: true"
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
  print_field "AdHocSigned" "$ad_hoc_signed"
else
  echo "RuntimeStatusAvailable: false"
fi

echo
echo "Latest production insertion probe"
latest_probe_json="$(latest_diagnostic_file 'production-insertion-probe-*.json')"
if [[ -n "$latest_probe_json" ]]; then
  print_field "ProbePath" "$latest_probe_json"
  print_field "ProbeGeneratedAt" "$(json_file_value "$latest_probe_json" generatedAt)"
  print_field "ProbeSuccess" "$(json_file_value "$latest_probe_json" success)"
  print_field "ProbeTargetCaptureSuccess" "$(json_file_value "$latest_probe_json" targetCaptureSuccess)"
  print_field "ProbeTraceProductionMethod" "$(json_file_value "$latest_probe_json" traceProductionMethod)"
else
  echo "ProbePath: none found"
fi

echo
echo "Eligibility"
microphone_detected="unknown"
if command -v system_profiler >/dev/null 2>&1; then
  if [[ "${#input_devices[@]}" -gt 0 ]]; then
    microphone_detected="true"
  else
    microphone_detected="false"
  fi
fi

install_smoke_eligible="false"
if [[ "$apple_silicon" == "true" && "$microphone_detected" != "false" ]]; then
  install_smoke_eligible="true"
fi
print_field "InstallSmokeEligible" "$install_smoke_eligible"

physical_stt_smoke_ready="false"
if [[ -f "$STATUS_JSON" ]] &&
   [[ "$apple_silicon" == "true" ]] &&
   [[ "$microphone_detected" == "true" ]] &&
   [[ "${input_pipeline_ready:-}" == "true" ]] &&
   [[ "${speech_model:-}" == "Ready" ]] &&
   [[ "${microphone_authorization:-}" == "authorized" ]]; then
  physical_stt_smoke_ready="true"
fi
print_field "PhysicalSTTSmokeReady" "$physical_stt_smoke_ready"

active_field_smoke_ready="false"
if [[ "$physical_stt_smoke_ready" == "true" && "${active_field_ready:-}" == "true" ]]; then
  active_field_smoke_ready="true"
fi
print_field "ActiveFieldSmokeReady" "$active_field_smoke_ready"

echo
echo "Next action"
if [[ "$apple_silicon" != "true" ]]; then
  echo "Not eligible: this is not an arm64 Apple Silicon Mac."
elif [[ "$microphone_detected" == "false" ]]; then
  echo "Attach or select an input microphone before running physical STT smoke."
elif [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Install the current PressTalk prerelease, then rerun this helper."
elif [[ ! -f "$STATUS_JSON" ]]; then
  echo "Run PressTalk bootstrap/startup, wait for runtime-status.json, then rerun this helper."
elif [[ "${input_pipeline_ready:-}" != "true" || "${speech_model:-}" != "Ready" ]]; then
  echo "Speech pipeline is not ready; collect smoke status before running a physical dictation smoke."
elif [[ "${active_field_ready:-}" != "true" ]]; then
  if [[ "${ad_hoc_signed:-}" == "true" && "${input_method_fallback:-}" == "recognized_disabled" ]]; then
    echo "Run logged-in desktop Repair Signing; do not reopen privacy panes for this state."
  else
    echo "Active-field insertion is not ready; collect smoke status and inspect the insertion blocker."
  fi
else
  echo "Ready for physical Fn/Option dictation smoke with active-field insertion proof."
fi
