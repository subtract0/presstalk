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

    var inputMonitoringEffective: Bool {
        inputMonitoringGranted || inputPipelineReady
    }

    var activeFieldInsertionReady: Bool {
        pasteAutomatically && (accessibilityGranted || inputMethodFallbackStatus == "ready")
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
        if adHocSigned && inputMethodFallbackStatus == "recognized_disabled" {
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
        if inputMonitoringGranted {
            return PressTalkPermissionLabel(text: "Granted", tone: .ready)
        }
        if inputPipelineReady {
            return PressTalkPermissionLabel(text: "Listener ready", tone: .ready)
        }
        return PressTalkPermissionLabel(text: "Preflight unavailable", tone: .warning)
    }

    var microphonePermissionLabel: PressTalkPermissionLabel {
        if microphoneGranted {
            return PressTalkPermissionLabel(text: "Granted", tone: .ready)
        }
        switch microphoneAuthorizationStatus {
        case "not_determined":
            return PressTalkPermissionLabel(text: "Not determined", tone: .warning)
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
                text: adHocSigned ? "Needs signing repair" : "Input method disabled",
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
