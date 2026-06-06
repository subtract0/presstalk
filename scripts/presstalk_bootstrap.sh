#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONTENTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$(cd "$APP_CONTENTS_DIR/.." && pwd)"
APP_BINARY="$APP_CONTENTS_DIR/MacOS/jarvistap"
LOCAL_CODESIGN_HELPER="$APP_CONTENTS_DIR/Resources/create-presstalk-local-codesign-identity.sh"
KARABINER_HELPER="$APP_CONTENTS_DIR/Resources/presstalk-karabiner-fallback.sh"
DISABLE_DICTATION_HELPER="$APP_CONTENTS_DIR/Resources/presstalk-disable-system-dictation.sh"
PLIST="$HOME/Library/LaunchAgents/com.am.jarvistap.plist"
WORKDIR="$HOME/Library/Application Support/JarvisTap"
LOG_OUT="$HOME/Library/Logs/jarvistap.out.log"
LOG_ERR="$HOME/Library/Logs/jarvistap.err.log"
TRACE_LOG="$HOME/Library/Logs/jarvistap_trace.log"
PATH_VALUE="${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
PRESSTALK_TRIGGER_KEY="${PRESSTALK_TRIGGER_KEY:-fn}"
PRESSTALK_BOOTSTRAP_STABLE_SIGNING="${PRESSTALK_BOOTSTRAP_STABLE_SIGNING:-1}"
PRESSTALK_OPEN_PERMISSION_PANES="${PRESSTALK_OPEN_PERMISSION_PANES:-0}"
PRESSTALK_AUTO_SHOW_SETUP_WINDOW="${PRESSTALK_AUTO_SHOW_SETUP_WINDOW:-0}"

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$WORKDIR"
touch "$LOG_OUT" "$LOG_ERR" "$TRACE_LOG"

terminate_existing_presstalk() {
  local pids=""
  pids="$(ps -axo pid=,command= | awk '
    index($0, "/PressTalk.app/Contents/MacOS/jarvistap") || index($0, "/JarvisTap.app/Contents/MacOS/jarvistap") {
      print $1
    }
  ')"
  if [[ -z "$pids" ]]; then
    return 0
  fi

  for pid in $pids; do
    kill "$pid" >/dev/null 2>&1 || true
  done

  for _ in {1..20}; do
    local remaining=""
    for pid in $pids; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        remaining="$remaining $pid"
      fi
    done
    if [[ -z "$remaining" ]]; then
      return 0
    fi
    sleep 0.2
  done

  for pid in $pids; do
    kill -KILL "$pid" >/dev/null 2>&1 || true
  done
}

# Homebrew-installed GitHub app archives can still arrive with Gatekeeper
# metadata on a fresh Mac. Clear that before launchd/LaunchServices tries to
# open the app, otherwise the first start can fail before PressTalk writes logs.
/usr/bin/xattr -dr com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1 || true
/usr/bin/xattr -dr com.apple.provenance "$APP_BUNDLE" >/dev/null 2>&1 || true

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
terminate_existing_presstalk

resign_with_local_identity_if_possible() {
  if [[ "$PRESSTALK_BOOTSTRAP_STABLE_SIGNING" != "1" ]]; then
    echo "Stable local signing skipped: PRESSTALK_BOOTSTRAP_STABLE_SIGNING=$PRESSTALK_BOOTSTRAP_STABLE_SIGNING"
    return 0
  fi
  if [[ ! -x "$LOCAL_CODESIGN_HELPER" ]]; then
    echo "Stable local signing skipped: helper missing from app bundle."
    return 0
  fi

  local output identity_hash
  if ! output="$("$LOCAL_CODESIGN_HELPER" 2>&1)"; then
    echo "$output"
    echo "Stable local signing skipped: could not prepare local code-signing identity."
    return 0
  fi
  identity_hash="$(printf '%s\n' "$output" | awk '/^Hash: / { print $2; exit }')"
  if [[ -z "$identity_hash" ]]; then
    echo "$output"
    echo "Stable local signing skipped: helper did not report an identity hash."
    return 0
  fi

  echo "Stable local signing identity: $identity_hash"
  if codesign --force --sign "$identity_hash" --timestamp=none --identifier "com.am.jarvistap" "$APP_BINARY" &&
    codesign --force --sign "$identity_hash" --timestamp=none "$APP_BUNDLE"; then
    echo "Stable local signing applied to PressTalk.app."
  else
    echo "Stable local signing skipped: codesign failed."
  fi
}

resign_with_local_identity_if_possible

if [[ -x "$KARABINER_HELPER" ]]; then
  /bin/bash "$KARABINER_HELPER" --disable >/dev/null 2>&1 || true
fi

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

open_env_arg() {
  local key="$1"
  local value="$2"
  printf '    <string>--env</string>\n'
  printf '    <string>%s=%s</string>\n' "$key" "$(xml_escape "$value")"
}

OPEN_ENV_ARGS="$(
  open_env_arg HOME "$HOME"
  open_env_arg PATH "$PATH_VALUE"
  open_env_arg JARVISTAP_AGENT_MODE "dictation"
  open_env_arg JARVISTAP_REQUEST_TIMEOUT_SECONDS "30"
  open_env_arg JARVISTAP_RELEASE_TAIL_PADDING_SECONDS "0.35"
  open_env_arg PRESSTALK_TRIGGER_KEY "$PRESSTALK_TRIGGER_KEY"
  open_env_arg PRESSTALK_AUTO_SHOW_SETUP_WINDOW "$PRESSTALK_AUTO_SHOW_SETUP_WINDOW"
  open_env_arg JARVISTAP_TRACE_LOG "$TRACE_LOG"
  open_env_arg JARVISTAP_WHISPERKIT_MODEL "openai_whisper-large-v3-v20240930_turbo_632MB"
  open_env_arg JARVISTAP_WHISPER_LANGUAGE "de"
  open_env_arg JARVISTAP_SAY_VOICE "Samantha"
)"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.am.jarvistap</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-g</string>
    <string>-j</string>
    <string>-W</string>
    <string>--stdout</string>
    <string>$LOG_OUT</string>
    <string>--stderr</string>
    <string>$LOG_ERR</string>
$OPEN_ENV_ARGS
    <string>$(xml_escape "$APP_BUNDLE")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$HOME</string>
    <key>PATH</key>
    <string>$PATH_VALUE</string>
    <key>JARVISTAP_AGENT_MODE</key>
    <string>dictation</string>
    <key>JARVISTAP_REQUEST_TIMEOUT_SECONDS</key>
    <string>30</string>
    <key>JARVISTAP_RELEASE_TAIL_PADDING_SECONDS</key>
    <string>0.35</string>
    <key>PRESSTALK_TRIGGER_KEY</key>
    <string>$PRESSTALK_TRIGGER_KEY</string>
    <key>PRESSTALK_AUTO_SHOW_SETUP_WINDOW</key>
    <string>$PRESSTALK_AUTO_SHOW_SETUP_WINDOW</string>
    <key>JARVISTAP_TRACE_LOG</key>
    <string>$TRACE_LOG</string>
    <key>JARVISTAP_WHISPERKIT_MODEL</key>
    <string>openai_whisper-large-v3-v20240930_turbo_632MB</string>
    <key>JARVISTAP_WHISPER_LANGUAGE</key>
    <string>de</string>
    <key>JARVISTAP_SAY_VOICE</key>
    <string>Samantha</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>$WORKDIR</string>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>LimitLoadToSessionType</key>
  <array>
    <string>Aqua</string>
  </array>
  <key>StandardOutPath</key>
  <string>$LOG_OUT</string>
  <key>StandardErrorPath</key>
  <string>$LOG_ERR</string>
</dict>
</plist>
PLIST

chmod 644 "$PLIST"
plutil -lint "$PLIST" >/dev/null

LAUNCHD_DOMAIN="gui/$(id -u)"
LAUNCHD_SERVICE="$LAUNCHD_DOMAIN/com.am.jarvistap"
launchctl enable "$LAUNCHD_SERVICE" >/dev/null 2>&1 || true
if ! launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST"; then
  echo "LaunchAgent bootstrap failed; enabling com.am.jarvistap and retrying." >&2
  launchctl enable "$LAUNCHD_SERVICE" >/dev/null 2>&1 || true
  launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST"
fi
launchctl kickstart -k "$LAUNCHD_SERVICE" >/dev/null 2>&1 || true

# Do not also `open -a` the app here. The LaunchAgent already starts it, and
# opening the app bundle separately can create a second live dictation agent.
if [[ "$PRESSTALK_OPEN_PERMISSION_PANES" == "1" ]]; then
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone" >/dev/null 2>&1 || true
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" >/dev/null 2>&1 || true
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
fi

cat <<EOF
PressTalk bootstrap completed.

Installed:
- LaunchAgent: $PLIST
- Stable local signing: $PRESSTALK_BOOTSTRAP_STABLE_SIGNING
- Open permission panes: $PRESSTALK_OPEN_PERMISSION_PANES
- Auto-show setup window: $PRESSTALK_AUTO_SHOW_SETUP_WINDOW

Next:
1. Use the PressTalk menu bar icon for Settings or diagnostics
2. Hold Fn/Globe to speak, then release to paste

To use another trigger, set PRESSTALK_TRIGGER_KEY before bootstrapping.
Supported values: fn, option, left_option, right_option, f5, trackpad_hold.

Optional legacy F5 fallback:
- PressTalk still ships a built-in F5 bridge helper:
  Enable:  /bin/bash "$KARABINER_HELPER" --enable
  Disable: /bin/bash "$KARABINER_HELPER" --disable
- PressTalk also still ships a helper that disables the Apple Dictation F5 binding:
  /bin/bash "$DISABLE_DICTATION_HELPER"
EOF
