#!/usr/bin/env bash
set -euo pipefail

LABEL="${PRESSTALK_LAUNCH_LABEL:-com.am.jarvistap}"
APP_BUNDLE="${PRESSTALK_APP_BUNDLE:-$HOME/Applications/PressTalk.app}"
if [[ ! -d "$APP_BUNDLE" && -d "/Applications/PressTalk.app" ]]; then
  APP_BUNDLE="/Applications/PressTalk.app"
fi

STATUS_JSON="${PRESSTALK_STATUS_JSON:-$HOME/Library/Application Support/JarvisTap/runtime-status.json}"
TRACE_LOG="${PRESSTALK_TRACE_LOG:-$HOME/Library/Logs/jarvistap_trace.log}"

section() {
  printf '\n== %s ==\n' "$1"
}

json_value() {
  local key_path="$1"
  if [[ -f "$STATUS_JSON" ]]; then
    plutil -extract "$key_path" raw -o - "$STATUS_JSON" 2>/dev/null || true
  fi
}

app_signature_value() {
  local key="$1"
  if [[ -d "$APP_BUNDLE" ]]; then
    codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 |
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

section "Machine"
hostname || true
uname -m || true
sw_vers 2>/dev/null || true

section "App"
echo "App bundle: $APP_BUNDLE"
if [[ -d "$APP_BUNDLE" ]]; then
  /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
  codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 |
    awk '/^Identifier=|^CDHash=|^Signature=|^Authority=|^TeamIdentifier=/ { print }'
  codesign -dr - "$APP_BUNDLE" 2>&1 |
    awk '/designated =>/ { sub(/^.*designated => /, "DesignatedRequirement="); print }'
else
  echo "PressTalk.app not found"
fi

section "LaunchAgent"
launchctl print "gui/$(id -u)/$LABEL" 2>&1 |
  awk '/state =|program =|pid =|PRESSTALK_TRIGGER_KEY|job state =/ { print }' || true

section "PressTalk Process"
LIVE_PROCESSES="$(presstalk_processes || true)"
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

section "Trace Tail"
if [[ -f "$TRACE_LOG" ]]; then
  tail -80 "$TRACE_LOG"
else
  echo "Trace log missing: $TRACE_LOG"
fi
