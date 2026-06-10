#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEM_APP_BINARY="/Applications/PressTalk.app/Contents/MacOS/jarvistap"
USER_APP_BINARY="$HOME/Applications/PressTalk.app/Contents/MacOS/jarvistap"
LEGACY_SYSTEM_APP_BINARY="/Applications/JarvisTap.app/Contents/MacOS/jarvistap"
LEGACY_USER_APP_BINARY="$HOME/Applications/JarvisTap.app/Contents/MacOS/jarvistap"
APP_BINARY="$USER_APP_BINARY"
if [[ ! -x "$APP_BINARY" && -x "$SYSTEM_APP_BINARY" ]]; then
  APP_BINARY="$SYSTEM_APP_BINARY"
fi
if [[ ! -x "$APP_BINARY" && -x "$LEGACY_USER_APP_BINARY" ]]; then
  APP_BINARY="$LEGACY_USER_APP_BINARY"
fi
if [[ ! -x "$APP_BINARY" && -x "$LEGACY_SYSTEM_APP_BINARY" ]]; then
  APP_BINARY="$LEGACY_SYSTEM_APP_BINARY"
fi
PRESSTALK_LAUNCHD_LABEL="${PRESSTALK_LAUNCHD_LABEL:-com.am.presstalk}"
LEGACY_LAUNCHD_LABELS="${PRESSTALK_LEGACY_LAUNCHD_LABELS:-com.am.jarvistap}"
PLIST="$HOME/Library/LaunchAgents/$PRESSTALK_LAUNCHD_LABEL.plist"
WORKDIR="$HOME/Library/Application Support/PressTalk"
LOG_OUT="$HOME/Library/Logs/presstalk.out.log"
LOG_ERR="$HOME/Library/Logs/presstalk.err.log"
TRACE_LOG="$HOME/Library/Logs/presstalk_trace.log"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "PressTalk.app is missing. Build it first:"
  echo "  bash $ROOT/scripts/build_jarvistap.sh"
  echo "Or install the public cask:"
  echo "  brew tap subtract0/presstalk && brew install --cask presstalk"
  exit 1
fi
APP_BUNDLE="$(cd "$(dirname "$APP_BINARY")/../.." && pwd)"
APP_INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

current_bundle_identifier() {
  /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_INFO_PLIST" 2>/dev/null || true
}

seed_trigger_key_default() {
  local bundle_id="$1"
  [[ -n "$bundle_id" ]] || return 0
  /usr/bin/defaults write "$bundle_id" JarvisTap.TriggerKey -string "$PRESSTALK_TRIGGER_KEY" >/dev/null 2>&1 || true
}

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

remove_legacy_launch_agents() {
  local domain="gui/$(id -u)"
  for label in $LEGACY_LAUNCHD_LABELS; do
    [[ -n "$label" && "$label" != "$PRESSTALK_LAUNCHD_LABEL" ]] || continue
    local legacy_plist="$HOME/Library/LaunchAgents/$label.plist"
    launchctl bootout "$domain" "$legacy_plist" >/dev/null 2>&1 || true
    launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
    launchctl disable "$domain/$label" >/dev/null 2>&1 || true
    rm -f "$legacy_plist"
  done
}

JARVISTAP_AGENT_MODE="${JARVISTAP_AGENT_MODE:-dictation}"
JARVISTAP_WHISPERKIT_MODEL="${JARVISTAP_WHISPERKIT_MODEL:-openai_whisper-large-v3-v20240930_turbo_632MB}"
JARVISTAP_WHISPER_LANGUAGE="${JARVISTAP_WHISPER_LANGUAGE:-auto}"
JARVISTAP_SAY_VOICE="${JARVISTAP_SAY_VOICE:-Samantha}"
JARVISTAP_REQUEST_TIMEOUT_SECONDS="${JARVISTAP_REQUEST_TIMEOUT_SECONDS:-30}"
JARVISTAP_RELEASE_TAIL_PADDING_SECONDS="${JARVISTAP_RELEASE_TAIL_PADDING_SECONDS:-0.35}"
PRESSTALK_ASR_BACKEND="${PRESSTALK_ASR_BACKEND:-${JARVISTAP_ASR_BACKEND:-parakeet-v3-ane}}"
PRESSTALK_STREAMING_ASR_BACKEND="${PRESSTALK_STREAMING_ASR_BACKEND:-${JARVISTAP_STREAMING_ASR_BACKEND:-parakeet-eou-320}}"
PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION="${PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION:-${JARVISTAP_ENABLE_STREAMING_TRANSCRIPTION:-1}}"
PRESSTALK_PARAKEET_QUALITY_FALLBACK="${PRESSTALK_PARAKEET_QUALITY_FALLBACK:-${JARVISTAP_PARAKEET_QUALITY_FALLBACK:-1}}"
PRESSTALK_PARAKEET_MIN_CONFIDENCE="${PRESSTALK_PARAKEET_MIN_CONFIDENCE:-${JARVISTAP_PARAKEET_MIN_CONFIDENCE:-0.96}}"
PRESSTALK_TRIGGER_KEY="${PRESSTALK_TRIGGER_KEY:-${JARVISTAP_TRIGGER_KEY:-fn}}"
PRESSTALK_AUTO_SHOW_SETUP_WINDOW="${PRESSTALK_AUTO_SHOW_SETUP_WINDOW:-${JARVISTAP_AUTO_SHOW_SETUP_WINDOW:-0}}"
PRESSTALK_OPEN_PERMISSION_PANES="${PRESSTALK_OPEN_PERMISSION_PANES:-${JARVISTAP_OPEN_PERMISSION_PANES:-0}}"
PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE="${PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE:-0}"
JARVISTAP_TRACE_LOG="${JARVISTAP_TRACE_LOG:-$TRACE_LOG}"
PATH_VALUE="${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
seed_trigger_key_default "$(current_bundle_identifier)"

/usr/bin/xattr -dr com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1 || true
/usr/bin/xattr -dr com.apple.provenance "$APP_BUNDLE" >/dev/null 2>&1 || true

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

ENV_BLOCK="  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PATH</key>
    <string>${PATH_VALUE}</string>
    <key>JARVISTAP_AGENT_MODE</key>
    <string>${JARVISTAP_AGENT_MODE}</string>
    <key>JARVISTAP_REQUEST_TIMEOUT_SECONDS</key>
    <string>${JARVISTAP_REQUEST_TIMEOUT_SECONDS}</string>
    <key>JARVISTAP_RELEASE_TAIL_PADDING_SECONDS</key>
    <string>${JARVISTAP_RELEASE_TAIL_PADDING_SECONDS}</string>
    <key>PRESSTALK_ASR_BACKEND</key>
    <string>${PRESSTALK_ASR_BACKEND}</string>
    <key>PRESSTALK_STREAMING_ASR_BACKEND</key>
    <string>${PRESSTALK_STREAMING_ASR_BACKEND}</string>
    <key>PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION</key>
    <string>${PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION}</string>
    <key>PRESSTALK_PARAKEET_QUALITY_FALLBACK</key>
    <string>${PRESSTALK_PARAKEET_QUALITY_FALLBACK}</string>
    <key>PRESSTALK_PARAKEET_MIN_CONFIDENCE</key>
    <string>${PRESSTALK_PARAKEET_MIN_CONFIDENCE}</string>
    <key>PRESSTALK_TRIGGER_KEY</key>
    <string>${PRESSTALK_TRIGGER_KEY}</string>
    <key>PRESSTALK_AUTO_SHOW_SETUP_WINDOW</key>
    <string>${PRESSTALK_AUTO_SHOW_SETUP_WINDOW}</string>
    <key>PRESSTALK_OPEN_PERMISSION_PANES</key>
    <string>${PRESSTALK_OPEN_PERMISSION_PANES}</string>
    <key>PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE</key>
    <string>${PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE}</string>
    <key>PRESSTALK_LAUNCHD_LABEL</key>
    <string>${PRESSTALK_LAUNCHD_LABEL}</string>
    <key>JARVISTAP_TRACE_LOG</key>
    <string>${JARVISTAP_TRACE_LOG}</string>
    <key>JARVISTAP_WHISPERKIT_MODEL</key>
    <string>${JARVISTAP_WHISPERKIT_MODEL}</string>
    <key>JARVISTAP_WHISPER_LANGUAGE</key>
    <string>${JARVISTAP_WHISPER_LANGUAGE}</string>
    <key>JARVISTAP_SAY_VOICE</key>
    <string>${JARVISTAP_SAY_VOICE}</string>"

if [[ -n "${JARVISTAP_PRINT_PARTIALS:-}" ]]; then
  ENV_BLOCK="$ENV_BLOCK
    <key>JARVISTAP_PRINT_PARTIALS</key>
    <string>${JARVISTAP_PRINT_PARTIALS}</string>"
fi

if [[ "$JARVISTAP_AGENT_MODE" == "codex-confirm-execute" ]]; then
  ENV_BLOCK="$ENV_BLOCK
    <key>JARVISTAP_CODEX_COMMAND</key>
    <string>${JARVISTAP_CODEX_COMMAND:-codex}</string>
    <key>JARVISTAP_CODEX_MODEL</key>
    <string>${JARVISTAP_CODEX_MODEL:-gpt-5.4}</string>
    <key>JARVISTAP_CODEX_PLAN_REASONING_EFFORT</key>
    <string>${JARVISTAP_CODEX_PLAN_REASONING_EFFORT:-medium}</string>
    <key>JARVISTAP_CODEX_EXEC_REASONING_EFFORT</key>
    <string>${JARVISTAP_CODEX_EXEC_REASONING_EFFORT:-high}</string>
    <key>JARVISTAP_CODEX_PLAN_TIMEOUT_SECONDS</key>
    <string>${JARVISTAP_CODEX_PLAN_TIMEOUT_SECONDS:-120}</string>
    <key>JARVISTAP_CODEX_WORKDIR</key>
    <string>${JARVISTAP_CODEX_WORKDIR:-$HOME}</string>"
fi

ENV_BLOCK="$ENV_BLOCK
  </dict>"

OPEN_ENV_ARGS="$(
  open_env_arg HOME "$HOME"
  open_env_arg PATH "$PATH_VALUE"
  open_env_arg JARVISTAP_AGENT_MODE "$JARVISTAP_AGENT_MODE"
  open_env_arg JARVISTAP_REQUEST_TIMEOUT_SECONDS "$JARVISTAP_REQUEST_TIMEOUT_SECONDS"
  open_env_arg JARVISTAP_RELEASE_TAIL_PADDING_SECONDS "$JARVISTAP_RELEASE_TAIL_PADDING_SECONDS"
  open_env_arg PRESSTALK_ASR_BACKEND "$PRESSTALK_ASR_BACKEND"
  open_env_arg PRESSTALK_STREAMING_ASR_BACKEND "$PRESSTALK_STREAMING_ASR_BACKEND"
  open_env_arg PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION "$PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION"
  open_env_arg PRESSTALK_TRIGGER_KEY "$PRESSTALK_TRIGGER_KEY"
  open_env_arg PRESSTALK_AUTO_SHOW_SETUP_WINDOW "$PRESSTALK_AUTO_SHOW_SETUP_WINDOW"
  open_env_arg PRESSTALK_OPEN_PERMISSION_PANES "$PRESSTALK_OPEN_PERMISSION_PANES"
  open_env_arg PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE "$PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE"
  open_env_arg PRESSTALK_LAUNCHD_LABEL "$PRESSTALK_LAUNCHD_LABEL"
  open_env_arg JARVISTAP_TRACE_LOG "$JARVISTAP_TRACE_LOG"
  open_env_arg JARVISTAP_WHISPERKIT_MODEL "$JARVISTAP_WHISPERKIT_MODEL"
  open_env_arg JARVISTAP_WHISPER_LANGUAGE "$JARVISTAP_WHISPER_LANGUAGE"
  open_env_arg JARVISTAP_SAY_VOICE "$JARVISTAP_SAY_VOICE"
  if [[ -n "${JARVISTAP_PRINT_PARTIALS:-}" ]]; then
    open_env_arg JARVISTAP_PRINT_PARTIALS "$JARVISTAP_PRINT_PARTIALS"
  fi
  if [[ "$JARVISTAP_AGENT_MODE" == "codex-confirm-execute" ]]; then
    open_env_arg JARVISTAP_CODEX_COMMAND "${JARVISTAP_CODEX_COMMAND:-codex}"
    open_env_arg JARVISTAP_CODEX_MODEL "${JARVISTAP_CODEX_MODEL:-gpt-5.4}"
    open_env_arg JARVISTAP_CODEX_PLAN_REASONING_EFFORT "${JARVISTAP_CODEX_PLAN_REASONING_EFFORT:-medium}"
    open_env_arg JARVISTAP_CODEX_EXEC_REASONING_EFFORT "${JARVISTAP_CODEX_EXEC_REASONING_EFFORT:-high}"
    open_env_arg JARVISTAP_CODEX_PLAN_TIMEOUT_SECONDS "${JARVISTAP_CODEX_PLAN_TIMEOUT_SECONDS:-120}"
    open_env_arg JARVISTAP_CODEX_WORKDIR "${JARVISTAP_CODEX_WORKDIR:-$HOME}"
  fi
)"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PRESSTALK_LAUNCHD_LABEL</string>
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
$ENV_BLOCK
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

remove_legacy_launch_agents
launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
terminate_existing_presstalk
LAUNCHD_DOMAIN="gui/$(id -u)"
LAUNCHD_SERVICE="$LAUNCHD_DOMAIN/$PRESSTALK_LAUNCHD_LABEL"
launchctl enable "$LAUNCHD_SERVICE" >/dev/null 2>&1 || true
if ! launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST"; then
  echo "LaunchAgent bootstrap failed; enabling $PRESSTALK_LAUNCHD_LABEL and retrying." >&2
  launchctl enable "$LAUNCHD_SERVICE" >/dev/null 2>&1 || true
  launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST"
fi
launchctl kickstart -k "$LAUNCHD_SERVICE"

echo "Installed and started: $PRESSTALK_LAUNCHD_LABEL"
echo "Mode: $JARVISTAP_AGENT_MODE"
echo "ASR backend: $PRESSTALK_ASR_BACKEND"
echo "Streaming ASR backend: $PRESSTALK_STREAMING_ASR_BACKEND"
echo "Streaming transcription: $PRESSTALK_ENABLE_STREAMING_TRANSCRIPTION"
echo "Parakeet quality fallback: $PRESSTALK_PARAKEET_QUALITY_FALLBACK"
echo "Parakeet min confidence: $PRESSTALK_PARAKEET_MIN_CONFIDENCE"
echo "Trigger: $PRESSTALK_TRIGGER_KEY"
echo "Auto-show setup window: $PRESSTALK_AUTO_SHOW_SETUP_WINDOW"
echo "Open permission panes: $PRESSTALK_OPEN_PERMISSION_PANES"
echo "Production insertion probe: $PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE"
echo "Trace: $JARVISTAP_TRACE_LOG"
echo "Tail live logs with:"
echo "  tail -f $JARVISTAP_TRACE_LOG"
