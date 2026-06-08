#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_APP_BUNDLE="$HOME/Applications/PressTalk.app"
STATUS_JSON="$HOME/Library/Application Support/JarvisTap/runtime-status.json"
DIAGNOSTICS_DIR="$HOME/Library/Application Support/JarvisTap/Diagnostics"
APP_BUNDLE="${PRESSTALK_APP_BUNDLE:-}"
TRIGGER_KEY="${PRESSTALK_TRIGGER_KEY:-}"
WRITE_DESKTOP_COMMAND=0
PROMPT=0
PROBE=0
DESKTOP_COMMAND_PATH="${PRESSTALK_ACCESSIBILITY_DESKTOP_COMMAND_PATH:-}"

usage() {
  cat <<EOF
Usage: presstalk-accessibility-handoff.sh [options]

Prepares a deliberate one-time Accessibility insertion handoff for PressTalk.
This is for Macs where microphone, trigger, and speech are ready, but the
InputMethodKit fallback remains recognized_disabled / enable_no_effect.

Options:
  --app-bundle PATH   PressTalk.app path. Defaults to the bundled app or
                      $DEFAULT_APP_BUNDLE.
  --trigger-key KEY   Trigger to preserve for probes. Default: runtime status,
                      then option_space.
  --preflight         Report current Accessibility and insertion status without
                      prompting or opening System Settings.
  --prompt            Run the exact installed app in Accessibility prompt mode.
                      This may open macOS Accessibility settings once.
  --probe             Run no-prompt Accessibility check, production insertion
                      probe, and repair verifier.
  --write-desktop-command
                      Write a double-clickable Desktop command that performs the
                      prompt, waits for user approval, then probes insertion.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-bundle)
      APP_BUNDLE="${2:-}"
      if [[ -z "$APP_BUNDLE" ]]; then
        echo "Missing value for --app-bundle" >&2
        exit 2
      fi
      shift 2
      ;;
    --trigger-key)
      TRIGGER_KEY="${2:-}"
      if [[ -z "$TRIGGER_KEY" ]]; then
        echo "Missing value for --trigger-key" >&2
        exit 2
      fi
      shift 2
      ;;
    --preflight)
      PROMPT=0
      PROBE=0
      PREFLIGHT=1
      shift
      ;;
    --prompt)
      PROMPT=1
      shift
      ;;
    --probe)
      PROBE=1
      shift
      ;;
    --write-desktop-command)
      WRITE_DESKTOP_COMMAND=1
      shift
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

PREFLIGHT="${PREFLIGHT:-0}"

if [[ -z "$APP_BUNDLE" ]]; then
  if [[ -f "$SCRIPT_DIR/../Info.plist" && -d "$SCRIPT_DIR/../MacOS" ]]; then
    APP_BUNDLE="$(cd "$SCRIPT_DIR/../.." && pwd)"
  else
    APP_BUNDLE="$DEFAULT_APP_BUNDLE"
  fi
fi

APP_RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
PROBE_RUNNER="$APP_RESOURCES_DIR/presstalk-run-production-insertion-probe.sh"
VERIFY_REPAIR="$APP_RESOURCES_DIR/presstalk-verify-repair-result.sh"
MACHINE_READINESS="$APP_RESOURCES_DIR/presstalk-machine-readiness.sh"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing PressTalk app bundle: $APP_BUNDLE" >&2
  exit 1
fi

if [[ -z "$TRIGGER_KEY" && -f "$STATUS_JSON" ]]; then
  TRIGGER_KEY="$(plutil -extract runtime.triggerKey raw -o - "$STATUS_JSON" 2>/dev/null || true)"
fi
TRIGGER_KEY="${TRIGGER_KEY:-option_space}"

json_value() {
  local path="$1"
  local key="$2"
  if [[ -f "$path" ]]; then
    plutil -extract "$key" raw -o - "$path" 2>/dev/null || true
  fi
}

status_value() {
  json_value "$STATUS_JSON" "$1"
}

shell_quote() {
  printf "'"
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

run_accessibility_probe() {
  local prompt_requested="$1"
  local timestamp stdout_path stderr_path open_status
  mkdir -p "$DIAGNOSTICS_DIR"
  timestamp="$(date -u '+%Y-%m-%dT%H-%M-%SZ')-$$"
  stdout_path="$DIAGNOSTICS_DIR/accessibility-handoff-$timestamp.stdout.json"
  stderr_path="$DIAGNOSTICS_DIR/accessibility-handoff-$timestamp.stderr.txt"

  open_status=0
  if /usr/bin/open \
    -n \
    -g \
    -j \
    -W \
    --stdout "$stdout_path" \
    --stderr "$stderr_path" \
    --env PRESSTALK_ACCESSIBILITY_TRUST_PROBE=1 \
    --env PRESSTALK_ACCESSIBILITY_TRUST_PROMPT="$prompt_requested" \
    --env PRESSTALK_OPEN_PERMISSION_PANES=0 \
    --env PRESSTALK_AUTO_SHOW_SETUP_WINDOW=0 \
    "$APP_BUNDLE" >/dev/null 2>&1; then
    open_status=0
  else
    open_status=$?
  fi

  echo "AccessibilityProbeStatus: $open_status"
  echo "AccessibilityProbeStdout: $stdout_path"
  echo "AccessibilityProbeStderr: $stderr_path"
  if [[ -f "$stdout_path" ]]; then
    echo "AccessibilityTrusted: $(json_value "$stdout_path" accessibilityTrusted)"
    echo "AccessibilityPromptRequested: $(json_value "$stdout_path" promptRequested)"
    echo "AccessibilityBundleIdentifier: $(json_value "$stdout_path" bundleIdentifier)"
    echo "AccessibilityCodeSignatureCDHash: $(json_value "$stdout_path" codeSignatureCDHash)"
    echo "AccessibilityCodeSignatureAuthority: $(json_value "$stdout_path" codeSignatureAuthority)"
  fi
}

write_desktop_command() {
  local command_path command_dir helper_path
  command_path="${DESKTOP_COMMAND_PATH:-$HOME/Desktop/Grant PressTalk Accessibility.command}"
  command_dir="$(dirname "$command_path")"
  helper_path="$SCRIPT_DIR/$(basename "$0")"

  mkdir -p "$command_dir"
  cat >"$command_path" <<EOF
#!/usr/bin/env bash
set -uo pipefail

clear
echo "PressTalk Accessibility insertion test"
echo
echo "This is only for active-field insertion on this Mac."
echo "Do not change Microphone, Input Monitoring, or signing settings here."
echo
echo "macOS may open Privacy & Security > Accessibility."
echo "Enable PressTalk.app for Accessibility, then return here."
echo

/bin/bash $(shell_quote "$helper_path") --app-bundle $(shell_quote "$APP_BUNDLE") --trigger-key $(shell_quote "$TRIGGER_KEY") --prompt

echo
echo "After enabling PressTalk in Accessibility, press Return to run"
echo "the insertion probe and verifier. If you did not change anything,"
echo "press Return anyway; the result will say what is still missing."
read -r _

/bin/bash $(shell_quote "$helper_path") --app-bundle $(shell_quote "$APP_BUNDLE") --trigger-key $(shell_quote "$TRIGGER_KEY") --probe
status=\$?

echo
if [[ "\$status" == "0" ]]; then
  echo "PressTalk Accessibility insertion test passed."
else
  echo "PressTalk Accessibility insertion test did not pass. Exit status: \$status"
fi
echo
echo "Press Return to close this window."
read -r _
exit "\$status"
EOF
  chmod 700 "$command_path"

  cat <<EOF
PressTalk Accessibility desktop command written

DesktopCommand: $command_path
App: $APP_BUNDLE
Trigger: $TRIGGER_KEY

This did not open System Settings, did not request Accessibility, did not run an
insertion probe, and did not change Microphone or Input Monitoring.

NextAction: From the logged-in desktop session, double-click the command,
enable only PressTalk in Accessibility if macOS asks, then let it run the probe.
EOF
}

print_preflight() {
  echo "PressTalk Accessibility handoff preflight"
  echo
  echo "App: $APP_BUNDLE"
  echo "Trigger: $TRIGGER_KEY"
  echo "RuntimeStatus: $STATUS_JSON"
  echo "AdHocSigned: $(status_value status.adHocSigned)"
  echo "CodeSignatureAuthority: $(status_value status.codeSignatureAuthority)"
  echo "InputMethodFallbackStatus: $(status_value permissions.inputMethodFallbackStatus)"
  echo "AccessibilityStatus: $(status_value permissions.accessibilityStatus)"
  echo "ActiveFieldInsertionReady: $(status_value runtime.activeFieldInsertionReady)"
  echo "ActiveFieldInsertionStatus: $(status_value runtime.activeFieldInsertionStatus)"
  echo "MicrophoneAuthorizationStatus: $(status_value permissions.microphoneAuthorizationStatus)"
  echo "InputMonitoringEffective: $(status_value permissions.inputMonitoringEffective)"
  echo
  run_accessibility_probe 0
  echo
  echo "This preflight did not prompt, did not open System Settings, and did not run insertion."
}

if [[ "$WRITE_DESKTOP_COMMAND" == "1" ]]; then
  write_desktop_command
  exit 0
fi

if [[ "$PREFLIGHT" == "1" ]]; then
  print_preflight
  exit 0
fi

if [[ "$PROMPT" == "1" ]]; then
  echo "Requesting Accessibility trust for the exact installed PressTalk app."
  echo "This may open macOS Accessibility settings once."
  run_accessibility_probe 1
fi

if [[ "$PROBE" == "1" ]]; then
  echo
  echo "Checking current Accessibility trust without prompting..."
  run_accessibility_probe 0

  if [[ -x "$PROBE_RUNNER" ]]; then
    echo
    echo "Running production insertion probe..."
    PRESSTALK_TRIGGER_KEY="$TRIGGER_KEY" /bin/bash "$PROBE_RUNNER" --json --timeout 14 || true
  else
    echo "Production insertion probe runner missing: $PROBE_RUNNER" >&2
  fi

  if [[ -x "$VERIFY_REPAIR" ]]; then
    echo
    echo "Running insertion verifier..."
    /bin/bash "$VERIFY_REPAIR"
  elif [[ -x "$MACHINE_READINESS" ]]; then
    echo
    echo "Running machine readiness..."
    /bin/bash "$MACHINE_READINESS"
  else
    echo "Verifier missing: $VERIFY_REPAIR" >&2
    exit 1
  fi
fi

if [[ "$PROMPT" != "1" && "$PROBE" != "1" ]]; then
  usage
fi
