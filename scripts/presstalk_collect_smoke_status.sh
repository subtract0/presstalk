#!/usr/bin/env bash
set -euo pipefail

LABEL="${PRESSTALK_LAUNCH_LABEL:-com.am.jarvistap}"
STATUS_JSON="${PRESSTALK_STATUS_JSON:-$HOME/Library/Application Support/JarvisTap/runtime-status.json}"
TRACE_LOG="${PRESSTALK_TRACE_LOG:-$HOME/Library/Logs/jarvistap_trace.log}"
DIAGNOSTICS_DIR="${PRESSTALK_DIAGNOSTICS_DIR:-$HOME/Library/Application Support/JarvisTap/Diagnostics}"

section() {
  printf '\n== %s ==\n' "$1"
}

json_file_value() {
  local file="$1"
  local key_path="$2"
  if [[ -f "$file" ]]; then
    plutil -extract "$key_path" raw -o - "$file" 2>/dev/null || true
  fi
}

json_value() {
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
  client="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  client="${client:-com.am.presstalk}"

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
  case "$(accessibility_tcc_auth_value)" in
    2) printf 'granted' ;;
    0) printf 'listed_disabled' ;;
    "") printf 'missing_or_unreadable' ;;
    *) printf 'present_non_granted' ;;
  esac
}

print_json_field_line() {
  local file="$1"
  local label="$2"
  local key_path="$3"
  local value
  value="$(json_file_value "$file" "$key_path")"
  echo "$label: ${value:-unknown}"
}

app_signature_value() {
  local key="$1"
  if [[ -d "$APP_BUNDLE" ]]; then
    codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 |
      awk -F= -v key="$key" '$1 == key { value = $2 } END { if (value != "") print value }'
  fi
}

print_bundle_signature() {
  local label="$1"
  local path="$2"

  echo "$label: $path"
  if [[ ! -d "$path" ]]; then
    echo "Bundle missing"
    return
  fi

  codesign -dv --verbose=4 "$path" 2>&1 |
    awk '/^Identifier=|^CDHash=|^Signature=|^Authority=|^TeamIdentifier=/ { print }'
  codesign -dr - "$path" 2>&1 |
    awk '/designated =>/ { sub(/^.*designated => /, "DesignatedRequirement="); print }'
}

bundle_signature_value() {
  local path="$1"
  local key="$2"
  if [[ -d "$path" ]]; then
    codesign -dv --verbose=4 "$path" 2>&1 |
      awk -F= -v key="$key" '$1 == key { value = $2 } END { if (value != "") print value }'
  fi
}

status_signature_value() {
  local key="$1"
  json_value codeSignatureSummary |
    awk -F= -v key="$key" '$1 == key { value = $2 } END { if (value != "") print value }'
}

sqlite_has_column() {
  local db="$1"
  local table="$2"
  local column="$3"
  sqlite3 "$db" "PRAGMA table_info($table);" 2>/dev/null |
    awk -F'|' -v column="$column" '$2 == column { found = 1 } END { exit found ? 0 : 1 }'
}

print_tcc_rows() {
  local label="$1"
  local db="$2"

  echo "$label: $db"
  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3 unavailable"
    return
  fi
  if [[ ! -e "$db" ]]; then
    echo "TCC database missing"
    return
  fi
  if [[ ! -r "$db" ]]; then
    echo "TCC database not readable by this process"
    return
  fi

  local services="'kTCCServiceMicrophone','kTCCServiceListenEvent','kTCCServiceAccessibility'"
  local clients="'com.am.presstalk','com.am.jarvistap'"
  local query
  if sqlite_has_column "$db" access auth_value; then
    query="
      SELECT
        service,
        client,
        client_type,
        auth_value,
        auth_reason,
        auth_version,
        CASE WHEN csreq IS NULL THEN 0 ELSE 1 END AS has_csreq,
        datetime(last_modified, 'unixepoch', 'localtime') AS last_modified
      FROM access
      WHERE service IN ($services)
        AND client IN ($clients)
      ORDER BY service, client;
    "
  elif sqlite_has_column "$db" access allowed; then
    query="
      SELECT
        service,
        client,
        client_type,
        allowed,
        prompt_count,
        CASE WHEN csreq IS NULL THEN 0 ELSE 1 END AS has_csreq,
        datetime(last_modified, 'unixepoch', 'localtime') AS last_modified
      FROM access
      WHERE service IN ($services)
        AND client IN ($clients)
      ORDER BY service, client;
    "
  else
    echo "TCC access table schema is not recognized"
    return
  fi

  local rows
  rows="$(sqlite3 -header -column "$db" "$query" 2>/dev/null || true)"
  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows"
  else
    echo "No PressTalk/JarvisTap rows for Microphone, Input Monitoring, or Accessibility"
  fi
}

print_tcc_code_requirements() {
  local label="$1"
  local db="$2"

  echo "$label: $db"
  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3 unavailable"
    return
  fi
  if ! command -v csreq >/dev/null 2>&1; then
    echo "csreq unavailable"
    return
  fi
  if [[ ! -e "$db" ]]; then
    echo "TCC database missing"
    return
  fi
  if [[ ! -r "$db" ]]; then
    echo "TCC database not readable by this process"
    return
  fi

  local services="'kTCCServiceMicrophone','kTCCServiceListenEvent','kTCCServiceAccessibility'"
  local clients="'com.am.presstalk','com.am.jarvistap'"
  local rows
  rows="$(
    sqlite3 -csv "$db" "
      SELECT service, client
      FROM access
      WHERE service IN ($services)
        AND client IN ($clients)
        AND csreq IS NOT NULL
      ORDER BY service, client;
    " 2>/dev/null || true
  )"

  if [[ -z "$rows" ]]; then
    echo "No decodable PressTalk/JarvisTap code requirements"
    return
  fi

  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-tcc-csreq.XXXXXX")"
  while IFS=, read -r service client; do
    [[ -z "$service" || -z "$client" ]] && continue
    local path="$tmpdir/$service-$client.csreq"
    if ! sqlite3 "$db" "
      SELECT writefile('$path', csreq)
      FROM access
      WHERE service='$service'
        AND client='$client'
        AND csreq IS NOT NULL
      LIMIT 1;
    " >/dev/null 2>&1; then
      echo "$service $client: could not write temporary csreq blob"
      continue
    fi
    local requirement
    requirement="$(csreq -r "$path" -t 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    echo "$service $client: ${requirement:-unavailable}"
  done <<<"$rows"
  rm -rf "$tmpdir"
}

print_repair_and_probe_status() {
  echo "Diagnostics directory: $DIAGNOSTICS_DIR"

  if [[ -f "$STATUS_JSON" ]]; then
    local ad_hoc_signed
    local input_method_fallback
    local accessibility_status
    local speech_model
    local input_listener
    local active_field_insertion_ready
    local active_field_insertion_status
    local microphone_authorization
    local input_monitoring_effective
    local code_signature_authority
    local accessibility_tcc_state
    ad_hoc_signed="$(json_value status.adHocSigned)"
    code_signature_authority="$(json_value status.codeSignatureAuthority)"
    input_method_fallback="$(json_value permissions.inputMethodFallbackStatus)"
    accessibility_status="$(json_value permissions.accessibilityStatus)"
    speech_model="$(json_value status.speechModel)"
    input_listener="$(json_value runtime.inputListener)"
    active_field_insertion_ready="$(json_value runtime.activeFieldInsertionReady)"
    active_field_insertion_status="$(json_value runtime.activeFieldInsertionStatus)"
    microphone_authorization="$(json_value permissions.microphoneAuthorizationStatus)"
    input_monitoring_effective="$(json_value permissions.inputMonitoringEffective)"
    accessibility_tcc_state="$(accessibility_tcc_summary)"

    echo "adHocSigned: ${ad_hoc_signed:-unknown}"
    echo "codeSignatureAuthority: ${code_signature_authority:-unknown}"
    echo "inputMethodFallbackStatus: ${input_method_fallback:-unknown}"
    echo "accessibilityStatus: ${accessibility_status:-unknown}"
    echo "accessibilityTCC: ${accessibility_tcc_state:-unknown}"
    echo "speechModel: ${speech_model:-unknown}"
    echo "inputListener: ${input_listener:-unknown}"
    echo "activeFieldInsertionReady: ${active_field_insertion_ready:-unknown}"
    echo "activeFieldInsertionStatus: ${active_field_insertion_status:-unknown}"
    echo "microphoneAuthorizationStatus: ${microphone_authorization:-unknown}"
    echo "inputMonitoringEffective: ${input_monitoring_effective:-unknown}"

    if [[ "$active_field_insertion_status" == "needs_signing_repair" ||
          ( "$input_method_fallback" == "recognized_disabled" && "$ad_hoc_signed" == "true" ) ]]; then
      cat <<EOF
Next action: from the logged-in desktop session, click Repair Signing in the PressTalk menu bar or Settings and approve only the PressTalk local signing password prompt.
No Microphone, Input Monitoring, or Accessibility re-grant is needed for this state.
EOF
    elif [[ "$input_method_fallback" == "recognized_disabled" ]]; then
      handoff_command=""
      handoff_command="$(accessibility_handoff_command_path)"
      if [[ -x "$handoff_command" ]]; then
        if [[ "$accessibility_tcc_state" == "listed_disabled" ]]; then
          cat <<EOF
Next action: macOS recognizes the PressTalk input method but leaves it disabled for this signed app.
Do not rerun signing repair or privacy panes for this state. PressTalk is already listed in Accessibility but disabled.
From the logged-in desktop, double-click:
$handoff_command
Turn on the existing PressTalk entry only, then let the command run the insertion probe and verifier.
EOF
        else
          cat <<EOF
Next action: macOS recognizes the PressTalk input method but leaves it disabled for this signed app.
Do not rerun signing repair or privacy panes for this state. From the logged-in desktop, double-click:
$handoff_command
That command grants only PressTalk Accessibility, then runs the insertion probe and verifier.
EOF
        fi
      elif [[ -x "$APP_BUNDLE/Contents/Resources/presstalk-accessibility-handoff.sh" ]]; then
        cat <<EOF
Next action: macOS recognizes the PressTalk input method but leaves it disabled for this signed app.
Do not rerun signing repair or privacy panes for this state. Write the desktop Accessibility handoff with:
/bin/bash "$APP_BUNDLE/Contents/Resources/presstalk-accessibility-handoff.sh" --write-desktop-command
EOF
      else
        cat <<EOF
Next action: macOS recognizes the PressTalk input method but leaves it disabled for this signed app.
Do not rerun signing repair or privacy panes for this state; inspect TIS enable-no-effect or use the Accessibility insertion path.
EOF
      fi
    elif [[ "$input_method_fallback" == "probe_only" || "$input_method_fallback" == "ready" ]]; then
      handoff_command=""
      handoff_command="$(accessibility_handoff_command_path)"
      if [[ -x "$handoff_command" ]]; then
        if [[ "$accessibility_tcc_state" == "listed_disabled" ]]; then
          cat <<EOF
Next action: speech and clipboard fallback are ready, but real-field auto-insert requires Accessibility for this exact PressTalk app.
PressTalk is already listed in Accessibility but disabled. From the logged-in desktop, double-click:
$handoff_command
Turn on the existing PressTalk entry only, then let the command run the insertion probe and verifier.
EOF
        else
          cat <<EOF
Next action: speech and clipboard fallback are ready, but real-field auto-insert requires Accessibility for this exact PressTalk app.
From the logged-in desktop, double-click:
$handoff_command
That command grants only PressTalk Accessibility, then runs the insertion probe and verifier.
EOF
        fi
      elif [[ -x "$APP_BUNDLE/Contents/Resources/presstalk-accessibility-handoff.sh" ]]; then
        cat <<EOF
Next action: speech and clipboard fallback are ready, but real-field auto-insert requires Accessibility for this exact PressTalk app.
Write the desktop Accessibility handoff with:
/bin/bash "$APP_BUNDLE/Contents/Resources/presstalk-accessibility-handoff.sh" --write-desktop-command
EOF
      else
        echo "Next action: speech and clipboard fallback are ready, but real-field auto-insert requires Accessibility for this exact PressTalk app."
      fi
    elif [[ -n "$input_method_fallback" ]]; then
      echo "Next action: inspect the input-method status above before changing permissions."
    fi
  else
    echo "Runtime status file missing: $STATUS_JSON"
  fi

  local latest_repair_log
  latest_repair_log="$(latest_diagnostic_file 'presstalk-signing-repair-*.log')"
  if [[ -n "$latest_repair_log" ]]; then
    echo
    echo "Latest signing repair log: $latest_repair_log"
    local latest_repair_pid_file="${latest_repair_log%.log}.pid"
    if [[ -f "$latest_repair_pid_file" ]]; then
      local latest_repair_pid
      latest_repair_pid="$(tr -dc '0-9' <"$latest_repair_pid_file" 2>/dev/null || true)"
      echo "Latest signing repair PID file: $latest_repair_pid_file"
      if [[ -n "$latest_repair_pid" ]] && kill -0 "$latest_repair_pid" >/dev/null 2>&1; then
        echo "Latest signing repair process: running pid=$latest_repair_pid"
      elif [[ -n "$latest_repair_pid" ]]; then
        echo "Latest signing repair process: not running pid=$latest_repair_pid"
      else
        echo "Latest signing repair process: PID file empty"
      fi
    fi
    tail -40 "$latest_repair_log" 2>/dev/null || true
  else
    echo
    echo "Latest signing repair log: none found"
  fi

  local latest_probe_json
  latest_probe_json="$(latest_diagnostic_file 'production-insertion-probe-*.json')"
  if [[ -n "$latest_probe_json" ]]; then
    echo
    echo "Latest production insertion probe: $latest_probe_json"
    print_json_field_line "$latest_probe_json" "generatedAt" generatedAt
    print_json_field_line "$latest_probe_json" "success" success
    print_json_field_line "$latest_probe_json" "reason" reason
    print_json_field_line "$latest_probe_json" "targetCaptureSuccess" targetCaptureSuccess
    print_json_field_line "$latest_probe_json" "targetCaptureFailureHint" targetCaptureFailureHint
    print_json_field_line "$latest_probe_json" "traceProductionMethod" traceProductionMethod
    print_json_field_line "$latest_probe_json" "traceCopyFallback" traceCopyFallback
    print_json_field_line "$latest_probe_json" "traceInputMethodEnableNoEffect" traceInputMethodEnableNoEffect
  else
    echo
    echo "Latest production insertion probe: none found"
  fi

  local latest_manual_json
  latest_manual_json="$(latest_diagnostic_file 'manual-trigger-smoke-*.json')"
  if [[ -n "$latest_manual_json" ]]; then
    echo
    echo "Latest manual physical trigger smoke: $latest_manual_json"
    print_json_field_line "$latest_manual_json" "generatedAt" generatedAt
    print_json_field_line "$latest_manual_json" "success" success
    print_json_field_line "$latest_manual_json" "reason" reason
    print_json_field_line "$latest_manual_json" "expectedTriggerKey" expectedTriggerKey
    print_json_field_line "$latest_manual_json" "expectedTriggerProof" expectedTriggerProof
    print_json_field_line "$latest_manual_json" "targetCaptureSuccess" targetCaptureSuccess
    print_json_field_line "$latest_manual_json" "targetCaptureFailureHint" targetCaptureFailureHint
    print_json_field_line "$latest_manual_json" "traceRegisteredHotKeyObserved" traceRegisteredHotKeyObserved
    print_json_field_line "$latest_manual_json" "traceFinalTranscript" traceFinalTranscript
  else
    echo
    echo "Latest manual physical trigger smoke: none found"
  fi
}

presstalk_processes() {
  ps -axo pid=,ppid=,command= |
    awk '
      (index($0, "/PressTalk.app/Contents/MacOS/jarvistap") ||
      index($0, "/JarvisTap.app/Contents/MacOS/jarvistap")) &&
      !index($0, " awk ") {
        print
      }
    '
}

live_app_bundle() {
  printf '%s\n' "$1" |
    awk '
      {
        for (i = 3; i <= NF; i++) {
          if ($i ~ /\/(PressTalk|JarvisTap)\.app\/Contents\/MacOS\/jarvistap$/) {
            sub(/\/Contents\/MacOS\/jarvistap$/, "", $i)
            print $i
            exit
          }
        }
      }
    '
}

LIVE_PROCESSES="$(presstalk_processes || true)"
if [[ -n "${PRESSTALK_APP_BUNDLE:-}" ]]; then
  APP_BUNDLE="$PRESSTALK_APP_BUNDLE"
else
  APP_BUNDLE="$(live_app_bundle "$LIVE_PROCESSES")"
  if [[ -z "$APP_BUNDLE" ]]; then
    APP_BUNDLE="$HOME/Applications/PressTalk.app"
    if [[ ! -d "$APP_BUNDLE" && -d "/Applications/PressTalk.app" ]]; then
      APP_BUNDLE="/Applications/PressTalk.app"
    fi
  fi
fi

section "Machine"
hostname || true
uname -m || true
sw_vers 2>/dev/null || true

section "App"
echo "App bundle: $APP_BUNDLE"
if [[ -d "$APP_BUNDLE" ]]; then
  /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
  print_bundle_signature "App signature" "$APP_BUNDLE"
else
  echo "PressTalk.app not found"
fi

section "Input Method"
BUNDLED_INPUT_METHOD="$APP_BUNDLE/Contents/Resources/PressTalkInputMethod.app"
INSTALLED_INPUT_METHOD="$HOME/Library/Input Methods/PressTalkInputMethod.app"
INPUT_METHOD_STATUS_HELPER="$APP_BUNDLE/Contents/Resources/presstalk-input-method-status.swift"
print_bundle_signature "Bundled input method" "$BUNDLED_INPUT_METHOD"
print_bundle_signature "Installed input method" "$INSTALLED_INPUT_METHOD"
BUNDLED_INPUT_METHOD_CDHASH="$(bundle_signature_value "$BUNDLED_INPUT_METHOD" CDHash)"
INSTALLED_INPUT_METHOD_CDHASH="$(bundle_signature_value "$INSTALLED_INPUT_METHOD" CDHash)"
echo "Bundled input method CDHash: ${BUNDLED_INPUT_METHOD_CDHASH:-unknown}"
echo "Installed input method CDHash: ${INSTALLED_INPUT_METHOD_CDHASH:-unknown}"
if [[ -n "$BUNDLED_INPUT_METHOD_CDHASH" && -n "$INSTALLED_INPUT_METHOD_CDHASH" &&
      "$BUNDLED_INPUT_METHOD_CDHASH" != "$INSTALLED_INPUT_METHOD_CDHASH" ]]; then
  echo "Warning: installed input method signature differs from the bundled input method."
fi
if [[ -f "$INPUT_METHOD_STATUS_HELPER" ]]; then
  echo "Read-only TIS status:"
  swift "$INPUT_METHOD_STATUS_HELPER" --json 2>&1 || true
else
  echo "Input method status helper missing: $INPUT_METHOD_STATUS_HELPER"
fi

section "LaunchAgent"
launchctl print "gui/$(id -u)/$LABEL" 2>&1 |
  awk '/state =|program =|pid =|PRESSTALK_TRIGGER_KEY|job state =/ { print }' || true

section "PressTalk Process"
if [[ -n "$LIVE_PROCESSES" ]]; then
  printf '%s\n' "$LIVE_PROCESSES"
else
  echo "No live PressTalk process found"
fi

section "Runtime Status"
if [[ -f "$STATUS_JSON" ]]; then
  cat "$STATUS_JSON"
  echo
else
  echo "Runtime status file missing: $STATUS_JSON"
fi

section "Status Consistency"
if [[ -f "$STATUS_JSON" ]]; then
  STATUS_PID="$(json_value app.processID)"
  STATUS_GENERATED_AT="$(json_value generatedAt)"
  STATUS_BUNDLE_IDENTIFIER="$(json_value app.bundleIdentifier)"
  STATUS_BUNDLE_PATH="$(json_value app.bundlePath)"
  STATUS_CDHASH="$(status_signature_value CDHash)"
  APP_BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  APP_CDHASH="$(app_signature_value CDHash)"
  LIVE_PIDS="$(printf '%s\n' "$LIVE_PROCESSES" | awk '{ print $1 }' | xargs 2>/dev/null || true)"

  echo "Status generatedAt: ${STATUS_GENERATED_AT:-unknown}"
  if [[ -f "$STATUS_JSON" ]]; then
    stat -f "Status mtime: %Sm" "$STATUS_JSON" 2>/dev/null || true
  fi
  echo "Status processID: ${STATUS_PID:-unknown}"
  echo "Live processIDs: ${LIVE_PIDS:-none}"
  echo "Status bundle identifier: ${STATUS_BUNDLE_IDENTIFIER:-unknown}"
  echo "Status bundle path: ${STATUS_BUNDLE_PATH:-unknown}"
  echo "App bundle path: ${APP_BUNDLE:-unknown}"
  echo "App bundle identifier: ${APP_BUNDLE_IDENTIFIER:-unknown}"
  echo "Status CDHash: ${STATUS_CDHASH:-unknown}"
  echo "App CDHash: ${APP_CDHASH:-unknown}"

  if [[ -n "$STATUS_PID" && -n "$LIVE_PIDS" ]]; then
    if ! printf ' %s ' "$LIVE_PIDS" | grep -F " $STATUS_PID " >/dev/null; then
      echo "Warning: runtime-status.json does not describe the live PressTalk process."
    fi
  fi
  if [[ -n "$STATUS_BUNDLE_IDENTIFIER" && -n "$APP_BUNDLE_IDENTIFIER" && "$STATUS_BUNDLE_IDENTIFIER" != "$APP_BUNDLE_IDENTIFIER" ]]; then
    echo "Warning: runtime-status.json bundle identifier differs from the installed app."
  fi
  if [[ -n "$STATUS_BUNDLE_PATH" && -n "$APP_BUNDLE" && "$STATUS_BUNDLE_PATH" != "$APP_BUNDLE" ]]; then
    echo "Warning: runtime-status.json bundle path differs from the inspected app."
  fi
  if [[ -n "$STATUS_CDHASH" && -n "$APP_CDHASH" && "$STATUS_CDHASH" != "$APP_CDHASH" ]]; then
    echo "Warning: runtime-status.json code signature differs from the installed app."
  fi
else
  echo "Runtime status file missing: $STATUS_JSON"
fi

section "TCC Rows Read-Only"
print_tcc_rows "User TCC" "$HOME/Library/Application Support/com.apple.TCC/TCC.db"
print_tcc_rows "System TCC" "/Library/Application Support/com.apple.TCC/TCC.db"

section "TCC Code Requirements Read-Only"
print_tcc_code_requirements "User TCC" "$HOME/Library/Application Support/com.apple.TCC/TCC.db"
print_tcc_code_requirements "System TCC" "/Library/Application Support/com.apple.TCC/TCC.db"

section "Repair And Probe Status"
print_repair_and_probe_status

section "Trace Tail"
if [[ -f "$TRACE_LOG" ]]; then
  tail -80 "$TRACE_LOG"
else
  echo "Trace log missing: $TRACE_LOG"
fi
