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
else
  echo "PressTalk.app not found"
fi

section "LaunchAgent"
launchctl print "gui/$(id -u)/$LABEL" 2>&1 |
  awk '/state =|program =|pid =|PRESSTALK_TRIGGER_KEY|job state =/ { print }' || true

section "PressTalk Process"
ps -axo pid=,ppid=,command= |
  awk '
    (index($0, "/PressTalk.app/Contents/MacOS/jarvistap") ||
    index($0, "/JarvisTap.app/Contents/MacOS/jarvistap")) &&
    !index($0, " awk ") {
      print
    }
  ' || true

section "Runtime Status"
if [[ -f "$STATUS_JSON" ]]; then
  cat "$STATUS_JSON"
  echo
else
  echo "Runtime status file missing: $STATUS_JSON"
fi

section "Trace Tail"
if [[ -f "$TRACE_LOG" ]]; then
  tail -80 "$TRACE_LOG"
else
  echo "Trace log missing: $TRACE_LOG"
fi
