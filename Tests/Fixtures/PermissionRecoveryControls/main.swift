import AppKit
import PressTalkCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}
func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let guide = FirstRunSetupWindowController()
var details = FirstRunSetupWindowController.Details()
details.triggerName = "Fn / Globe"
details.microphoneAuthorization = "authorized"
details.modelState = .ready
var trusted = false
guide.onReadConditions = {
    .init(microphoneCaptureVerified: true, inputMonitoringGranted: true,
          accessibilityGranted: trusted, speechModelReady: true,
          firstDictationDelivered: false, triggerRequiresInputMonitoring: true,
          triggerRequiresAccessibility: true)
}
guide.onReadDetails = { details }
var opened = 0, rechecked = 0, restarted = 0, renewed = 0, revealed = 0
guide.onOpenAccessibilitySettings = { opened += 1 }
guide.onRecheckPermissions = { rechecked += 1 }
guide.onRestartForPermissions = { restarted += 1; return true }
guide.onRenewPermission = { renewed += 1 }
guide.onShowCurrentApp = { revealed += 1 }

let views = descendants(guide.window!.contentView!)
func button(_ id: String) -> NSButton {
    views.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == id }!
}
func text(_ id: String) -> String {
    views.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == id }!.stringValue
}
let primary = button("setup.primary")
let check = button("setup.recheckAccess")
let show = button("setup.showCurrentApp")

guide.refresh()
require(primary.title == "Open System Settings", "Permission action names an outdated OS pane")
require(opened + restarted + renewed == 0, "Rendering caused a prompt, restart or reset")
primary.performClick(nil)
require(opened == 1, "Explicit permission action is not connected")

details.permissionRecoveryState = .waitingForReturn
guide.refresh(); primary.performClick(nil)
require(rechecked == 1 && opened == 1, "Returning from Settings repeats the permission prompt")
check.performClick(nil)
require(rechecked == 2, "Nonprompting access recheck is disconnected")

details.permissionRecoveryState = .restartToRefresh
guide.refresh(); primary.performClick(nil)
require(restarted == 1, "One explicit restart is not connected")
details.permissionRecoveryState = .renewPermission
guide.refresh()
require(primary.title == "Renew PressTalk Permission", "Stale identity has no recovery action")
require(text("setup.detail").contains("fresh approval"), "Renewal hides the need for user consent")
primary.performClick(nil)
require(renewed == 1, "Permission renewal is not connected")

details.recordingOrProcessing = true
guide.refresh()
require(!primary.isEnabled && !check.isEnabled, "Recovery can interrupt dictation")
// Invoke the target directly as well: disabling a control is not a safety guard.
app.sendAction(primary.action!, to: primary.target, from: primary)
app.sendAction(check.action!, to: check.target, from: check)
require(renewed == 1 && rechecked == 2, "Direct actions bypassed the recording guard")
details.recordingOrProcessing = false

details.permissionRecoveryState = .systemApprovalRequired
guide.refresh()
require(primary.title == "Open System Settings" && !show.isHidden,
        "Failed renewal does not offer the current app and actual approval step")
primary.performClick(nil); show.performClick(nil)
require(opened == 2 && revealed == 1 && renewed == 1 && restarted == 1,
        "Post-renewal state repeats recovery instead of waiting for real consent")
details.permissionRecoveryMessage = "macOS did not accept this renewal. Your other permissions were not changed."
guide.refresh()
require(text("setup.detail") == details.permissionRecoveryMessage, "Renewal failure message was lost")

trusted = true
details.permissionRecoveryMessage = ""
details.permissionRecoveryState = .ready
guide.refresh()
require(text("setup.step") == "Your first dictation", "Actual permission grant did not advance setup")
require(restarted == 1 && renewed == 1, "A grant triggered extra recovery")
print("PASS: permission recovery controls, callbacks, busy guards and bounded recovery")
