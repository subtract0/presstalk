#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/Sources/JarvisTap/main.swift"
DEVICE_SOURCE="$REPO_ROOT/Sources/JarvisTap/AudioInputDeviceCandidate.swift"

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
require_absent "whisperKit.audioProcessor.stopRecording()" "PressTalk must route live recorder teardown through the safe AVAudioEngine stop path"
require_absent "whisperKit.clearState()" "WhisperKit clearState calls stopRecording directly and must not bypass safe recorder teardown"
for blocked_device_name in shure mv7 airpods camo zoom iphone; do
  if rg -qi "contains\\(\"$blocked_device_name\"\\)" "$DEVICE_SOURCE"; then
    echo "FAIL: microphone selection must not hard-code user-specific hardware or app names: $blocked_device_name"
    exit 1
  fi
done
require_contains "private var liveCapturedAudioSamples: [Float] = []" "PressTalk-owned live audio buffer is required for stable long holds"
require_contains "private var activeCaptureSessionID: UInt64 = 0" "Capture sessions must be identified so stale recorder callbacks are ignored"
require_contains "private var activeCaptureEngineStarted = false" "Release handling must distinguish no speech from a microphone startup race"
require_contains "private var retiredAudioEngines:" "Retired AVAudioEngine instances must be retained briefly to avoid teardown use-after-free crashes"
require_contains "safelyStopLiveAudioRecording(whisperKit: whisperKit, reason: \"release_tail\")" "Release-tail recorder stop must use the safe AVAudioEngine teardown path"
require_contains "safelyStopLiveAudioRecording(whisperKit: whisperKit, reason: \"stale_capture_start\")" "Late-started stale recorder stop must use the safe AVAudioEngine teardown path"
require_contains "processor.audioEngine = nil" "Safe teardown must detach the stopped engine from WhisperKit after retaining it"
require_contains "appendLiveCapturedAudioSamples(samples, sessionID: captureSessionID)" "Recorder callbacks must be scoped to the active capture session"
require_contains "selectionSource = \"system_default\"" "Audio input selection must honor the user's macOS default input first"
require_contains "selectionSource = \"non_bluetooth_fallback\"" "Bluetooth default input must be avoidable through a generic physical-input fallback"
require_contains "defaultInput.isBluetoothLike" "Bluetooth default input handling must be based on transport class, not device names"
require_contains 'rankedCandidates.first(where: { $0.isPhysicalInput })' "Bluetooth fallback must prefer a generic physical input"
require_contains "setDefaultCoreAudioInputDeviceID(selectedAudioInput.id)" "Non-default input recovery must promote the chosen input through CoreAudio"
require_contains "kAudioHardwarePropertyDefaultInputDevice" "Input promotion must target the macOS default input device"
require_contains "Audio input default promotion verified" "Input promotion must be traced and verified"
require_contains "Audio input selected source=" "Audio input diagnostics must report whether the system default or a generic fallback was selected"
require_absent "let liveInputDeviceID = selectedAudioInput?.isDefault == true ? nil : selectedAudioInput?.id" "PressTalk must not route non-default inputs through WhisperKit's explicit-device path"
require_contains "startRecordingLive(inputDeviceID: nil)" "Recording must use AVAudioEngine's stable macOS default-input path"
require_contains "case audioUnavailable(String)" "Zero-buffer microphone failures must have a distinct presentation state"
require_contains "No Audio Input" "Zero-buffer microphone failures must not present as unclear speech"
require_contains "finishProcessing(reason: \"audio_no_buffers\")" "Zero-buffer microphone failures must be diagnosed distinctly from no-speech"
require_contains "No speech captured because selected audio input produced no buffers" "Zero-buffer microphone failures must log the selected input"
require_absent "startLiveCaptureStallWatchdog" "PressTalk must not grow special-case audio fallback ladders"
require_absent "capture_stall_fallback" "PressTalk must not keep the removed explicit-device stall fallback path"
require_contains "Audio recording engine started after session ended; stopping stale capture session=" "Late-started AVAudioEngine sessions must be stopped instead of leaking into later holds"
require_contains "No speech captured because audio engine was not ready before release" "Short holds before AVAudioEngine startup must be reported as capture-not-ready"
require_contains "The microphone was still starting. Hold again." "The user-facing capture-not-ready message must not regress to misleading no-speech text"
require_contains "finishProcessing(reason: \"capture_not_ready\")" "Diagnostics must record capture-not-ready distinctly from no speech"
require_contains "Short no-speech hold suppressed; returning presentation to ready" "Suppressed short-hold no-speech must not leave the menu bar stuck in processing/STT"
require_contains "finishProcessing(" "Processing paths must keep resetting internal busy state"
require_contains "reason: captureDurationSeconds >= shortHoldNoSpeechSuppressionSeconds ? \"no_speech\" : \"no_speech_suppressed_short_hold\"" "Short-hold no-speech suppression must stay explicit in diagnostics"

echo "PASS capture_lifecycle_source"
