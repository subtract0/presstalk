import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum ModifierStateCleanup {
    static func releaseLatchedAlternateAfterInsertionIfNeeded(
        triggerKey: JarvisTapSettingsStore.TriggerKeyOption,
        reason: String,
        trace: (String) -> Void
    ) {
        guard !triggerUsesAlternateModifier(triggerKey) else { return }

        let hidFlags = CGEventSource.flagsState(.hidSystemState)
        let sessionFlags = CGEventSource.flagsState(.combinedSessionState)
        guard hidFlags.contains(.maskAlternate) || sessionFlags.contains(.maskAlternate) else { return }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        for keyCode in [CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption)] {
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                keyUp.flags = []
                keyUp.post(tap: .cgSessionEventTap)
            }
        }

        trace(
            "Released latched Option modifier after insertion reason=\(reason) hid_flags=0x\(String(hidFlags.rawValue, radix: 16)) session_flags=0x\(String(sessionFlags.rawValue, radix: 16))"
        )
    }

    private static func triggerUsesAlternateModifier(
        _ triggerKey: JarvisTapSettingsStore.TriggerKeyOption
    ) -> Bool {
        switch triggerKey {
        case .optionSpace, .option, .leftOption, .rightOption:
            return true
        case .fn, .trackpadHold, .f5:
            return false
        }
    }
}
