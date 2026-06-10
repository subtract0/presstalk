#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_SOURCE="$REPO_ROOT/Sources/JarvisTap/PressTalkRuntimeStatus.swift"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-permission-labels-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

cat >"$TEST_TMPDIR/PermissionStatusLabelTest.swift" <<'SWIFT'
import Foundation

@main
enum PermissionStatusLabelTest {
    static func makeStatus(
        inputMonitoringGranted: Bool = false,
        microphoneGranted: Bool = true,
        microphoneAuthorizationStatus: String = "authorized",
        accessibilityGranted: Bool = false,
        inputPipelineReady: Bool = true,
        inputListenerStatus: String = "hid:listen_only",
        triggerKey: String = "option",
        selectedTriggerObserved: Bool = false,
        pasteAutomatically: Bool = true,
        inputMethodFallbackStatus: String = "probe_only",
        adHocSigned: Bool = false,
        codeSignatureAuthority: String = "PressTalk Local Development Code Signing"
    ) -> PressTalkRuntimeStatus {
        PressTalkRuntimeStatus(
            bundleIdentifier: "com.am.presstalk",
            inputMonitoringGranted: inputMonitoringGranted,
            microphoneGranted: microphoneGranted,
            microphoneAuthorizationStatus: microphoneAuthorizationStatus,
            accessibilityGranted: accessibilityGranted,
            inputPipelineReady: inputPipelineReady,
            inputListenerStatus: inputListenerStatus,
            triggerKey: triggerKey,
            selectedTriggerObserved: selectedTriggerObserved,
            pasteAutomatically: pasteAutomatically,
            inputMethodFallbackStatus: inputMethodFallbackStatus,
            systemDictationHotkeyDisabled: true,
            adHocSigned: adHocSigned,
            permissionPaneOpeningAllowed: false,
            speechModelStatus: "Ready",
            asrBackend: "parakeet-v3-ane",
            streamingASRBackend: "parakeet-eou-320",
            realtimePartialTranscriptionEnabled: true,
            asrMode: "parakeet_v3_ane_final_pass_with_parakeet_eou_320_true_streaming_partials",
            f5BridgeStatus: "Fn / Globe ready",
            codeSignatureIdentifier: "com.am.presstalk",
            codeSignatureCDHash: "abc123",
            codeSignatureAuthority: codeSignatureAuthority
        )
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            Foundation.exit(1)
        }
    }

    static func main() {
        let modifierListenOnly = makeStatus()
        require(!modifierListenOnly.inputMonitoringEffective, "modifier triggers must not treat a listen-only event tap as effective")
        require(modifierListenOnly.inputMonitoringStatus == "writable_key_tap_unavailable", "modifier listen-only status should identify writable tap failure")
        require(modifierListenOnly.inputMonitoringPermissionLabel.text == "Writable key tap unavailable", "modifier listen-only label should not say listener ready")
        require(modifierListenOnly.inputMonitoringPermissionLabel.tone == .warning, "modifier listen-only label should use warning tone")

        let modifierWritable = makeStatus(inputListenerStatus: "hid:default")
        require(modifierWritable.inputMonitoringEffective, "modifier triggers should accept a writable event tap")
        require(modifierWritable.inputMonitoringPermissionLabel.text == "Listener ready", "writable listener without preflight should be labelled ready")
        require(modifierWritable.inputMonitoringPermissionLabel.tone == .ready, "writable listener should use ready tone")

        let registeredHotkeyReady = makeStatus(inputListenerStatus: "carbon:registered", triggerKey: "option_space")
        require(registeredHotkeyReady.inputMonitoringEffective, "registered hotkey trigger should be effective without writable event tap")
        require(registeredHotkeyReady.inputMonitoringStatus == "registered_hotkey_ready", "registered hotkey status should not ask for Input Monitoring")
        require(registeredHotkeyReady.inputMonitoringPermissionLabel.text == "Registered hotkey ready", "registered hotkey should have a specific ready label")
        require(registeredHotkeyReady.inputMonitoringPermissionLabel.tone == .ready, "registered hotkey ready label should use ready tone")
        require(!registeredHotkeyReady.readyWithoutPermissionPaneWork, "registered hotkey without Accessibility should not be active-field ready")

        let registeredHotkeyAccessible = makeStatus(accessibilityGranted: true, inputListenerStatus: "carbon:registered", triggerKey: "option_space")
        require(registeredHotkeyAccessible.readyWithoutPermissionPaneWork, "registered hotkey with Accessibility should be ready without permission pane work")

        let registeredHotkeyUnavailable = makeStatus(inputListenerStatus: "carbon:register_failed_-9878", triggerKey: "option_space")
        require(!registeredHotkeyUnavailable.inputMonitoringEffective, "failed registered hotkey trigger should not be effective")
        require(registeredHotkeyUnavailable.inputMonitoringStatus == "registered_hotkey_unavailable", "failed registered hotkey should report hotkey unavailability")
        require(registeredHotkeyUnavailable.inputMonitoringPermissionLabel.text == "Registered hotkey unavailable", "failed registered hotkey should not be labelled as a permission grant")

        let trackpadListenOnly = makeStatus(triggerKey: "trackpad_hold")
        require(!trackpadListenOnly.inputMonitoringEffective, "trackpad hold should wait for observed pointer input")
        require(trackpadListenOnly.inputMonitoringStatus == "waiting_for_trackpad_event", "trackpad listen-only status should wait for observed pointer input")
        require(trackpadListenOnly.inputMonitoringPermissionLabel.text == "Waiting for trackpad event", "trackpad listen-only listener should not be labelled ready before input arrives")

        let trackpadObserved = makeStatus(triggerKey: "trackpad_hold", selectedTriggerObserved: true)
        require(trackpadObserved.inputMonitoringEffective, "trackpad hold should accept a listen-only tap after pointer input is observed")
        require(trackpadObserved.inputMonitoringPermissionLabel.text == "Listener ready", "observed trackpad listener should be labelled ready")

        let readyNoPane = trackpadObserved
        require(readyNoPane.microphonePermissionLabel.text == "Granted", "authorized microphone must be labelled granted")
        require(readyNoPane.microphonePermissionLabel.tone == .ready, "authorized microphone must use ready tone")
        require(readyNoPane.accessibilityPermissionLabel.text == "Accessibility required", "probe-only input method must not be labelled active-field ready")
        require(readyNoPane.accessibilityPermissionLabel.tone == .warning, "probe-only input method should use warning tone")
        require(readyNoPane.activeFieldInsertionStatus == "blocked_accessibility_required", "probe-only input method should require Accessibility for active-field insertion")

        let accessibilityReady = makeStatus(accessibilityGranted: true)
        require(accessibilityReady.accessibilityPermissionLabel.text == "Granted", "trusted Accessibility must be labelled granted")
        require(accessibilityReady.accessibilityPermissionLabel.tone == .ready, "trusted Accessibility must use ready tone")
        require(accessibilityReady.activeFieldInsertionReady, "trusted Accessibility should prove active-field insertion readiness")
        require(accessibilityReady.activeFieldInsertionStatus == "ready_accessibility", "trusted Accessibility should be the active insertion path")

        let inputMethodReadyButUntrusted = makeStatus(inputMethodFallbackStatus: "ready")
        require(!inputMethodReadyButUntrusted.activeFieldInsertionReady, "enabled input method must not prove arbitrary real-field insertion")
        require(inputMethodReadyButUntrusted.accessibilityPermissionLabel.text == "Accessibility required", "enabled input method without AX should still require Accessibility")
        require(inputMethodReadyButUntrusted.activeFieldInsertionStatus == "blocked_accessibility_required", "enabled input method without AX should not be active-field ready")

        let clientUnavailable = makeStatus(inputListenerStatus: "carbon:registered", triggerKey: "option_space", inputMethodFallbackStatus: "client_unavailable")
        require(!clientUnavailable.activeFieldInsertionReady, "recent input-method client failure must not be marked active-field ready")
        require(!clientUnavailable.readyWithoutPermissionPaneWork, "recent input-method client failure must not pass ready-without-pane checks")
        require(clientUnavailable.accessibilityPermissionLabel.text == "Input method client unavailable", "recent input-method client failure should be labelled explicitly")
        require(clientUnavailable.accessibilityPermissionLabel.tone == .warning, "recent input-method client failure should use warning tone")
        require(clientUnavailable.activeFieldInsertionStatus == "blocked_client_unavailable", "recent input-method client failure should block active-field insertion")

        let acknowledgementTimeout = makeStatus(inputMethodFallbackStatus: "ack_timeout")
        require(!acknowledgementTimeout.activeFieldInsertionReady, "input-method ack timeout must not be marked active-field ready")
        require(acknowledgementTimeout.accessibilityPermissionLabel.text == "Input method unresponsive", "input-method ack timeout should be labelled explicitly")
        require(acknowledgementTimeout.activeFieldInsertionStatus == "blocked_ack_timeout", "input-method ack timeout should block active-field insertion")

        let mbp1Repair = makeStatus(inputMethodFallbackStatus: "recognized_disabled", adHocSigned: true)
        require(mbp1Repair.accessibilityPermissionLabel.text == "Needs signing repair", "ad-hoc recognized-disabled state should point to signing repair")
        require(mbp1Repair.activeFieldInsertionStatus == "needs_signing_repair", "ad-hoc recognized-disabled state should not ask for permission re-grants")
        require(!mbp1Repair.readyWithoutPermissionPaneWork, "signing repair state should not be marked ready without pane work")

        let mbp1PostRepair = makeStatus(inputMethodFallbackStatus: "recognized_disabled", adHocSigned: false)
        require(mbp1PostRepair.accessibilityPermissionLabel.text == "Input method disabled", "local-signing recognized-disabled state should not keep asking for signing repair")
        require(mbp1PostRepair.activeFieldInsertionStatus == "blocked_recognized_disabled", "local-signing recognized-disabled state should stay a TIS/input-method blocker")

        let disabledInputMethod = makeStatus(
            inputMethodFallbackStatus: "recognized_disabled",
            adHocSigned: false,
            codeSignatureAuthority: "Developer ID Application"
        )
        require(disabledInputMethod.accessibilityPermissionLabel.text == "Input method disabled", "non-PressTalk signing state should not be labelled signing repair")
        require(disabledInputMethod.activeFieldInsertionStatus == "blocked_recognized_disabled", "non-PressTalk disabled input method should stay a generic blocker")

        let copyOnly = makeStatus(pasteAutomatically: false, inputMethodFallbackStatus: "unknown")
        require(copyOnly.accessibilityPermissionLabel.text == "Optional; copy only", "copy-only mode should not require Accessibility")
        require(copyOnly.activeFieldInsertionStatus == "copy_only", "copy-only mode should be explicit")

        print("PASS permission_status_labels")
    }
}
SWIFT

swiftc "$STATUS_SOURCE" "$TEST_TMPDIR/PermissionStatusLabelTest.swift" -o "$TEST_TMPDIR/PermissionStatusLabelTest"
"$TEST_TMPDIR/PermissionStatusLabelTest"
