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
        inputMethodFallbackStatus: String = "ready",
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
        require(readyNoPane.accessibilityPermissionLabel.text == "Input method ready", "enabled input method fallback must not be labelled missing Accessibility")
        require(readyNoPane.accessibilityPermissionLabel.tone == .ready, "enabled input method fallback must use ready tone")
        require(readyNoPane.activeFieldInsertionStatus == "ready_input_method", "input method fallback should prove active-field insertion readiness")

        let mbp1Repair = makeStatus(inputMethodFallbackStatus: "recognized_disabled", adHocSigned: true)
        require(mbp1Repair.accessibilityPermissionLabel.text == "Needs signing repair", "ad-hoc recognized-disabled state should point to signing repair")
        require(mbp1Repair.activeFieldInsertionStatus == "needs_signing_repair", "ad-hoc recognized-disabled state should not ask for permission re-grants")

        let mbp1TrustRepair = makeStatus(inputMethodFallbackStatus: "recognized_disabled", adHocSigned: false)
        require(mbp1TrustRepair.accessibilityPermissionLabel.text == "Needs signing repair", "local-signing recognized-disabled state should point to signing repair")
        require(mbp1TrustRepair.activeFieldInsertionStatus == "needs_signing_repair", "local-signing recognized-disabled state should not ask for permission re-grants")

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
