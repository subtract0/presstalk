struct PressTalkPermissionLabel {
    enum Tone: String {
        case ready
        case warning
        case secondary
    }

    let text: String
    let tone: Tone
}

struct PressTalkRuntimeStatus {
    let bundleIdentifier: String
    let inputMonitoringGranted: Bool
    let microphoneGranted: Bool
    let microphoneAuthorizationStatus: String
    let accessibilityGranted: Bool
    let inputPipelineReady: Bool
    let inputListenerStatus: String
    let triggerKey: String
    let selectedTriggerObserved: Bool
    let pasteAutomatically: Bool
    let inputMethodFallbackStatus: String
    let systemDictationHotkeyDisabled: Bool
    let adHocSigned: Bool
    let permissionPaneOpeningAllowed: Bool
    let speechModelStatus: String
    let f5BridgeStatus: String
    let codeSignatureIdentifier: String
    let codeSignatureCDHash: String
    let codeSignatureAuthority: String

    var triggerRequiresWritableEventTap: Bool {
        switch triggerKey {
        case "fn", "option", "left_option", "right_option":
            return true
        default:
            return false
        }
    }

    var triggerUsesRegisteredHotKey: Bool {
        triggerKey == "option_space"
    }

    var inputListenerInstalled: Bool {
        inputListenerStatus.contains(":default") ||
            inputListenerStatus.contains(":listen_only") ||
            inputListenerStatus.contains("carbon:registered")
    }

    var writableEventTapInstalled: Bool {
        inputListenerStatus.contains(":default")
    }

    var inputMonitoringEffective: Bool {
        guard inputPipelineReady else {
            return false
        }
        if triggerRequiresWritableEventTap {
            return writableEventTapInstalled
        }
        if triggerUsesRegisteredHotKey {
            return inputListenerInstalled
        }
        if triggerKey == "trackpad_hold" {
            return inputListenerInstalled && selectedTriggerObserved
        }
        return inputListenerInstalled
    }

    var inputMonitoringStatus: String {
        if triggerUsesRegisteredHotKey {
            return inputMonitoringEffective ? "registered_hotkey_ready" : "registered_hotkey_unavailable"
        }
        if inputMonitoringEffective {
            return inputMonitoringGranted ? "preflight_granted" : "listener_ready_preflight_unavailable"
        }
        if triggerRequiresWritableEventTap && inputListenerInstalled {
            return "writable_key_tap_unavailable"
        }
        if triggerKey == "trackpad_hold" && inputListenerInstalled && !selectedTriggerObserved {
            return "waiting_for_trackpad_event"
        }
        if inputMonitoringGranted {
            return "preflight_granted_listener_unavailable"
        }
        return "preflight_unavailable"
    }

    var inputMonitoringStatusDescription: String {
        switch inputMonitoringStatus {
        case "preflight_granted":
            return "preflight granted"
        case "listener_ready_preflight_unavailable":
            return "listener ready; preflight unavailable"
        case "writable_key_tap_unavailable":
            return "writable key tap unavailable"
        case "waiting_for_trackpad_event":
            return "listener installed; waiting for trackpad event"
        case "registered_hotkey_ready":
            return "registered hotkey ready"
        case "registered_hotkey_unavailable":
            return "registered hotkey unavailable"
        case "preflight_granted_listener_unavailable":
            return "preflight granted; listener unavailable"
        default:
            return "preflight unavailable"
        }
    }

    var activeFieldInsertionReady: Bool {
        pasteAutomatically && (accessibilityGranted || inputMethodFallbackStatus == "ready")
    }

    var readyWithoutPermissionPaneWork: Bool {
        inputMonitoringEffective && microphoneGranted && activeFieldInsertionReady
    }

    var localSigningRepairNeeded: Bool {
        inputMethodFallbackStatus == "recognized_disabled" && adHocSigned
    }

    var activeFieldInsertionStatus: String {
        guard pasteAutomatically else {
            return "copy_only"
        }
        if accessibilityGranted {
            return "ready_accessibility"
        }
        if inputMethodFallbackStatus == "ready" {
            return "ready_input_method"
        }
        if localSigningRepairNeeded {
            return "needs_signing_repair"
        }
        return "blocked_\(inputMethodFallbackStatus)"
    }

    var codeSignatureSummary: String {
        if codeSignatureCDHash != "unknown" {
            return "CDHash \(codeSignatureCDHash)"
        }
        if codeSignatureAuthority != "unknown" {
            return codeSignatureAuthority
        }
        return "signature unknown"
    }

    var inputMonitoringPermissionLabel: PressTalkPermissionLabel {
        if triggerUsesRegisteredHotKey {
            if inputMonitoringEffective {
                return PressTalkPermissionLabel(text: "Registered hotkey ready", tone: .ready)
            }
            return PressTalkPermissionLabel(text: "Registered hotkey unavailable", tone: .warning)
        }
        if inputMonitoringEffective && inputMonitoringGranted {
            return PressTalkPermissionLabel(text: "Granted", tone: .ready)
        }
        if inputMonitoringEffective {
            return PressTalkPermissionLabel(text: "Listener ready", tone: .ready)
        }
        if triggerRequiresWritableEventTap && inputListenerInstalled {
            return PressTalkPermissionLabel(text: "Writable key tap unavailable", tone: .warning)
        }
        if triggerKey == "trackpad_hold" && inputListenerInstalled && !selectedTriggerObserved {
            return PressTalkPermissionLabel(text: "Waiting for trackpad event", tone: .warning)
        }
        if inputMonitoringGranted {
            return PressTalkPermissionLabel(text: "Granted, listener unavailable", tone: .warning)
        }
        return PressTalkPermissionLabel(text: "Preflight unavailable", tone: .warning)
    }

    var microphonePermissionLabel: PressTalkPermissionLabel {
        if microphoneGranted {
            return PressTalkPermissionLabel(text: "Granted", tone: .ready)
        }
        switch microphoneAuthorizationStatus {
        case "not_determined":
            return PressTalkPermissionLabel(text: "Needs microphone approval", tone: .warning)
        case "denied":
            return PressTalkPermissionLabel(text: "Preflight denied", tone: .warning)
        case "restricted":
            return PressTalkPermissionLabel(text: "Restricted", tone: .warning)
        default:
            return PressTalkPermissionLabel(text: "Preflight unavailable", tone: .warning)
        }
    }

    var accessibilityPermissionLabel: PressTalkPermissionLabel {
        if accessibilityGranted {
            return PressTalkPermissionLabel(text: "Granted", tone: .ready)
        }
        if !pasteAutomatically {
            return PressTalkPermissionLabel(text: "Optional; copy only", tone: .secondary)
        }
        switch inputMethodFallbackStatus {
        case "ready":
            return PressTalkPermissionLabel(text: "Input method ready", tone: .ready)
        case "recognized_disabled":
            return PressTalkPermissionLabel(
                text: localSigningRepairNeeded ? "Needs signing repair" : "Input method disabled",
                tone: .warning
            )
        case "recognized_not_selectable":
            return PressTalkPermissionLabel(text: "Input method blocked", tone: .warning)
        default:
            return PressTalkPermissionLabel(text: "Input method unavailable", tone: .warning)
        }
    }

    static let placeholder = PressTalkRuntimeStatus(
        bundleIdentifier: "unknown",
        inputMonitoringGranted: false,
        microphoneGranted: false,
        microphoneAuthorizationStatus: "unknown",
        accessibilityGranted: false,
        inputPipelineReady: false,
        inputListenerStatus: "Checking...",
        triggerKey: "unknown",
        selectedTriggerObserved: false,
        pasteAutomatically: true,
        inputMethodFallbackStatus: "unknown",
        systemDictationHotkeyDisabled: true,
        adHocSigned: false,
        permissionPaneOpeningAllowed: false,
        speechModelStatus: "Checking...",
        f5BridgeStatus: "Checking...",
        codeSignatureIdentifier: "unknown",
        codeSignatureCDHash: "unknown",
        codeSignatureAuthority: "unknown"
    )
}
