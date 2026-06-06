#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_CONTENTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$(cd "$APP_CONTENTS_DIR/.." && pwd)"
APP_BINARY="$APP_CONTENTS_DIR/MacOS/jarvistap"
KARABINER_HELPER="$APP_CONTENTS_DIR/Resources/presstalk-karabiner-fallback.sh"
DISABLE_DICTATION_HELPER="$APP_CONTENTS_DIR/Resources/presstalk-disable-system-dictation.sh"
PLIST="$HOME/Library/LaunchAgents/com.am.jarvistap.plist"
WORKDIR="$HOME/Library/Application Support/JarvisTap"
LOG_OUT="$HOME/Library/Logs/jarvistap.out.log"
LOG_ERR="$HOME/Library/Logs/jarvistap.err.log"
TRACE_LOG="$HOME/Library/Logs/jarvistap_trace.log"
PATH_VALUE="${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
PRESSTALK_TRIGGER_KEY="${PRESSTALK_TRIGGER_KEY:-fn}"

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$WORKDIR"
touch "$LOG_OUT" "$LOG_ERR" "$TRACE_LOG"

# Homebrew-installed GitHub app archives can still arrive quarantined on a fresh Mac.
# Clear that before launchd tries to exec the app, otherwise launchd may report OS_REASON_EXEC.
/usr/bin/xattr -dr com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1 || true

if [[ -x "$KARABINER_HELPER" ]]; then
  /bin/bash "$KARABINER_HELPER" --disable >/dev/null 2>&1 || true
fi

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.am.jarvistap</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_BINARY</string>
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

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/$(id -u)/com.am.jarvistap" >/dev/null 2>&1 || true

# Do not also `open -a` the app here. The LaunchAgent already starts it, and
# opening the app bundle separately can create a second live dictation agent.
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone" >/dev/null 2>&1 || true
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" >/dev/null 2>&1 || true
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true

cat <<EOF
PressTalk bootstrap completed.

Installed:
- LaunchAgent: $PLIST

Next:
1. Allow PressTalk microphone access
2. Allow PressTalk input monitoring / accessibility
3. Hold Fn/Globe to speak, then release to paste

To use another trigger, set PRESSTALK_TRIGGER_KEY before bootstrapping.
Supported values: fn, option, left_option, right_option, f5, trackpad_hold.

Optional legacy F5 fallback:
- PressTalk still ships a built-in F5 bridge helper:
  Enable:  /bin/bash "$KARABINER_HELPER" --enable
  Disable: /bin/bash "$KARABINER_HELPER" --disable
- PressTalk also still ships a helper that disables the Apple Dictation F5 binding:
  /bin/bash "$DISABLE_DICTATION_HELPER"
EOF
