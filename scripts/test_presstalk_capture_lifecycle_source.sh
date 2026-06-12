#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/Sources/JarvisTap/main.swift"

require_contains() {
  local needle="$1"
  local message="$2"
  if ! rg -q --fixed-strings "$needle" "$SOURCE"; then
    echo "FAIL: $message"
    echo "missing: $needle"
    exit 1
  fi
}

require_absent() {
  local needle="$1"
  local message="$2"
  if rg -q --fixed-strings "$needle" "$SOURCE"; then
    echo "FAIL: $message"
    echo "unexpected: $needle"
    exit 1
  fi
}

require_absent "audioProcessor.audioSamples" "PressTalk must not read WhisperKit's mutable live audio buffer directly"
require_contains "private var liveCapturedAudioSamples: [Float] = []" "PressTalk-owned live audio buffer is required for stable long holds"
require_contains "private var activeCaptureSessionID: UInt64 = 0" "Capture sessions must be identified so stale recorder callbacks are ignored"
require_contains "private var activeCaptureEngineStarted = false" "Release handling must distinguish no speech from a microphone startup race"
require_contains "appendLiveCapturedAudioSamples(samples, sessionID: captureSessionID)" "Recorder callbacks must be scoped to the active capture session"
require_contains "Audio recording engine started after session ended; stopping stale capture session=" "Late-started AVAudioEngine sessions must be stopped instead of leaking into later holds"
require_contains "No speech captured because audio engine was not ready before release" "Short holds before AVAudioEngine startup must be reported as capture-not-ready"
require_contains "The microphone was still starting. Hold again." "The user-facing capture-not-ready message must not regress to misleading no-speech text"
require_contains "finishProcessing(reason: \"capture_not_ready\")" "Diagnostics must record capture-not-ready distinctly from no speech"

echo "PASS capture_lifecycle_source"
