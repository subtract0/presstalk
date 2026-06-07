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
        pasteAutomatically: Bool = true,
        inputMethodFallbackStatus: String = "ready",
        adHocSigned: Bool = false
    ) -> PressTalkRuntimeStatus {
        PressTalkRuntimeStatus(
            bundleIdentifier: "com.am.presstalk",
            inputMonitoringGranted: inputMonitoringGranted,
            microphoneGranted: microphoneGranted,
            microphoneAuthorizationStatus: microphoneAuthorizationStatus,
            accessibilityGranted: accessibilityGranted,
            inputPipelineReady: inputPipelineReady,
            inputListenerStatus: "hid:listen_only",
            pasteAutomatically: pasteAutomatically,
            inputMethodFallbackStatus: inputMethodFallbackStatus,
            systemDictationHotkeyDisabled: true,
            adHocSigned: adHocSigned,
            permissionPaneOpeningAllowed: false,
            speechModelStatus: "Ready",
            f5BridgeStatus: "Fn / Globe ready",
            codeSignatureIdentifier: "com.am.presstalk",
            codeSignatureCDHash: "abc123",
            codeSignatureAuthority: "PressTalk Local Development Code Signing"
        )
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            Foundation.exit(1)
        }
    }

    static func main() {
        let readyNoPane = makeStatus()
        require(readyNoPane.inputMonitoringPermissionLabel.text == "Listener ready", "effective input listener must not be labelled missing")
        require(readyNoPane.inputMonitoringPermissionLabel.tone == .ready, "effective input listener must use ready tone")
        require(readyNoPane.microphonePermissionLabel.text == "Granted", "authorized microphone must be labelled granted")
        require(readyNoPane.microphonePermissionLabel.tone == .ready, "authorized microphone must use ready tone")
        require(readyNoPane.accessibilityPermissionLabel.text == "Input method ready", "enabled input method fallback must not be labelled missing Accessibility")
        require(readyNoPane.accessibilityPermissionLabel.tone == .ready, "enabled input method fallback must use ready tone")
        require(readyNoPane.activeFieldInsertionStatus == "ready_input_method", "input method fallback should prove active-field insertion readiness")

        let mbp1Repair = makeStatus(inputMethodFallbackStatus: "recognized_disabled", adHocSigned: true)
        require(mbp1Repair.accessibilityPermissionLabel.text == "Needs signing repair", "ad-hoc recognized-disabled state should point to signing repair")
        require(mbp1Repair.activeFieldInsertionStatus == "needs_signing_repair", "ad-hoc recognized-disabled state should not ask for permission re-grants")

        let copyOnly = makeStatus(pasteAutomatically: false, inputMethodFallbackStatus: "unknown")
        require(copyOnly.accessibilityPermissionLabel.text == "Optional; copy only", "copy-only mode should not require Accessibility")
        require(copyOnly.activeFieldInsertionStatus == "copy_only", "copy-only mode should be explicit")

        print("PASS permission_status_labels")
    }
}
SWIFT

swiftc "$STATUS_SOURCE" "$TEST_TMPDIR/PermissionStatusLabelTest.swift" -o "$TEST_TMPDIR/PermissionStatusLabelTest"
"$TEST_TMPDIR/PermissionStatusLabelTest"
