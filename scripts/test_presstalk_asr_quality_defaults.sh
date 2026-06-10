#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/Sources/JarvisTap/main.swift"
BOOTSTRAP="$REPO_ROOT/scripts/presstalk_bootstrap.sh"
INSTALLER="$REPO_ROOT/scripts/install_jarvistap_launchd.sh"

require_contains() {
  local path="$1"
  local needle="$2"
  local message="$3"
  if ! grep -Fq "$needle" "$path"; then
    echo "FAIL: $message"
    echo "Missing in $path: $needle"
    exit 1
  fi
}

require_not_contains() {
  local path="$1"
  local needle="$2"
  local message="$3"
  if grep -Fq "$needle" "$path"; then
    echo "FAIL: $message"
    echo "Unexpected in $path: $needle"
    exit 1
  fi
}

bash -n "$BOOTSTRAP"
bash -n "$INSTALLER"

require_contains "$SOURCE" 'env["PRESSTALK_PARAKEET_QUALITY_FALLBACK"]' "runtime must read Parakeet quality fallback setting"
require_contains "$SOURCE" 'env["PRESSTALK_PARAKEET_MIN_CONFIDENCE"]' "runtime must read Parakeet confidence threshold"
require_contains "$SOURCE" '0.96' "runtime must keep the default Parakeet confidence threshold"
require_contains "$SOURCE" "Parakeet v3 ANE transcript accepted but quality fallback requested" "runtime must log accepted Parakeet quality fallback"
require_contains "$SOURCE" "Using accepted Parakeet v3 ANE transcript fallback after Whisper candidates were empty, implausible, or too short" "runtime must preserve accepted Parakeet transcript when Whisper fallback is unusable or truncated"
require_contains "$SOURCE" "Whisper candidate deferred because it is much shorter than accepted Parakeet recall candidate" "runtime must detect truncated Whisper fallback candidates"
require_contains "$SOURCE" '"asrBackend": status.asrBackend' "runtime status JSON must record the active ASR backend"
require_contains "$SOURCE" '"asrMode": status.asrMode' "runtime status JSON must record whether this is final-pass or realtime partial mode"
require_contains "$SOURCE" '"realtimePartialTranscriptionEnabled": status.realtimePartialTranscriptionEnabled' "runtime status JSON must record realtime partial transcription state"
require_contains "$SOURCE" 'parakeet_v3_ane_final_pass' "runtime must expose the current Parakeet ANE final-pass mode"

require_contains "$BOOTSTRAP" 'PRESSTALK_ASR_BACKEND="${PRESSTALK_ASR_BACKEND:-${JARVISTAP_ASR_BACKEND:-parakeet-v3-ane}}"' "bootstrap must default to Parakeet v3 ANE"
require_contains "$BOOTSTRAP" 'JARVISTAP_WHISPER_LANGUAGE="${JARVISTAP_WHISPER_LANGUAGE:-auto}"' "bootstrap must default language detection to auto"
require_contains "$BOOTSTRAP" 'PRESSTALK_PARAKEET_QUALITY_FALLBACK="${PRESSTALK_PARAKEET_QUALITY_FALLBACK:-${JARVISTAP_PARAKEET_QUALITY_FALLBACK:-1}}"' "bootstrap must default quality fallback on"
require_contains "$BOOTSTRAP" 'PRESSTALK_PARAKEET_MIN_CONFIDENCE="${PRESSTALK_PARAKEET_MIN_CONFIDENCE:-${JARVISTAP_PARAKEET_MIN_CONFIDENCE:-0.96}}"' "bootstrap must default the confidence threshold"

require_contains "$INSTALLER" 'PRESSTALK_ASR_BACKEND="${PRESSTALK_ASR_BACKEND:-${JARVISTAP_ASR_BACKEND:-parakeet-v3-ane}}"' "LaunchAgent installer must default to Parakeet v3 ANE"
require_contains "$INSTALLER" 'JARVISTAP_WHISPER_LANGUAGE="${JARVISTAP_WHISPER_LANGUAGE:-auto}"' "LaunchAgent installer must default language detection to auto"
require_contains "$INSTALLER" 'PRESSTALK_PARAKEET_QUALITY_FALLBACK="${PRESSTALK_PARAKEET_QUALITY_FALLBACK:-${JARVISTAP_PARAKEET_QUALITY_FALLBACK:-1}}"' "LaunchAgent installer must default quality fallback on"
require_contains "$INSTALLER" 'PRESSTALK_PARAKEET_MIN_CONFIDENCE="${PRESSTALK_PARAKEET_MIN_CONFIDENCE:-${JARVISTAP_PARAKEET_MIN_CONFIDENCE:-0.96}}"' "LaunchAgent installer must default the confidence threshold"
require_not_contains "$INSTALLER" 'JARVISTAP_ASR_BACKEND:-whisperkit' "LaunchAgent installer must not silently default to WhisperKit"

echo "PASS asr_quality_defaults"
