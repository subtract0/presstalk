import AppKit
import Foundation
import PressTalkCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func spin() { RunLoop.current.run(until: Date().addingTimeInterval(0.06)) }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let domain = "com.am.presstalk.app-wiring-test.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
let delegate = JarvisTapApp()
delegate.runtimeStatusURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PRESSTALK_WIRING_STATUS_FILE"]!)
delegate.settingsStore = JarvisTapSettingsStore(config: delegate.config, defaults: defaults)
delegate.settingsStore.firstDictationDelivered = true
delegate.licenseStore = PressTalkLicenseStore(defaults: defaults,
    env: ["PRESSTALK_ENTITLEMENT_OVERRIDE": "founder"], anchorStores: [])
// Exercise the real actions during a simulated busy dictation. The production
// guard must show the guide without installing a listener or loading a model.
delegate.isProcessing = true
delegate.settingsWindowController = delegate.makeSettingsWindowController()
let settingsWindow = delegate.settingsWindowController!.window!
let buttons = descendants(settingsWindow.contentView!).compactMap { $0 as? NSButton }
let setup = buttons.first { $0.accessibilityIdentifier() == "settings.runSetupCheck" }!
setup.performClick(nil)
guard let guide = delegate.firstRunSetupWindowController else { fatalError("Settings setup action never constructed the guide") }
require(guide.window!.isVisible, "Settings setup action did not show a window")
require(delegate.setupNeedsFreshDictation, "Setup accepted an old dictation as a fresh check")
require(!delegate.inputPipelineReady && delegate.whisperWarmupTask == nil,
    "Setup check interrupted the busy dictation to start another pipeline")
guide.close(finished: false)
let menu = delegate.makeStatusMenu()
for title in ["Run Setup…", "Run Setup Check", "Test Dictation Shortcut…"] {
    let item = menu.items.first { $0.title == title }!
    app.sendAction(item.action!, to: item.target, from: item)
    require(guide.window!.isVisible, "Menu action did not show the built-in check: \(title)")
    guide.close(finished: false)
}
let shortcutTest = buttons.first { $0.accessibilityIdentifier() == "settings.testDictation" }!
shortcutTest.performClick(nil)
require(guide.window!.isVisible, "Settings shortcut test depends on an absent developer helper")
guide.close(finished: false)
require(!delegate.settingsStore.firstRunSetupCompleted, "Closing a check persisted false success")

// Keep OS facts under fixture control; the app's production observer and
// confirmation closures remain exactly those wired by presentFirstRunSetup.
guide.onReadConditions = {
    .init(microphoneCaptureVerified: true, inputMonitoringGranted: true,
        accessibilityGranted: true, speechModelReady: true,
        firstDictationDelivered: !delegate.setupNeedsFreshDictation,
        triggerRequiresInputMonitoring: true, triggerRequiresAccessibility: true)
}
guide.onReadDetails = {
    var details = FirstRunSetupWindowController.Details()
    details.microphoneAuthorization = "authorized"; details.modelState = .ready
    return details
}
let practice = descendants(guide.window!.contentView!).compactMap { $0 as? NSTextView }
    .first { $0.accessibilityIdentifier() == "setup.practice" }!
practice.string = ""
guide.beginDictation()
delegate.recordDelivery("Every word of this sentence must arrive.", reachedTargetApp: true)
let primary = descendants(guide.window!.contentView!).compactMap { $0 as? NSButton }
    .first { $0.accessibilityIdentifier() == "setup.primary" }!
let deadline = Date().addingTimeInterval(2)
while primary.title != "Confirm full sentence" && Date() < deadline { spin() }
require(primary.title == "Confirm full sentence", "The production delivery observer never reached the guide")
require(delegate.setupNeedsFreshDictation, "Posting delivery falsely completed the visible check")
practice.string = "Every word of this sentence"
guide.refresh()
require(delegate.setupNeedsFreshDictation, "Truncated text passed the production setup check")
practice.string = "Every word of this sentence must arrive. "
guide.refresh()
require(!delegate.setupNeedsFreshDictation,
    "The real delivery observer or confirmation callback is disconnected")
let done = descendants(guide.window!.contentView!).compactMap { $0 as? NSButton }
    .first { $0.accessibilityIdentifier() == "setup.primary" }!
require(done.title == "Done", "The real app never reached Done")
done.performClick(nil)
require(delegate.settingsStore.firstRunSetupCompleted, "Done did not persist completion through the app callback")

// Exercise the existing production guard, which prevents a setup retry from
// replacing Ready with Warming. This catches removal of the guard at its call site.
delegate.isProcessing = false
delegate.whisperLoadState = .ready
delegate.present(.warming)
if case .ready = delegate.presentationState {} else { require(false, "Ready was overwritten by a stale warming request") }
// A real key handler must not open a second microphone during the check.
delegate.setupMicrophoneProbeInProgress = true
delegate.handlePress(.configuredKey, source: .modifierKey)
require(!delegate.isRecording && !delegate.activeCaptureEngineStarted,
    "The actual key handler opened capture during a microphone check")
if case .busy = delegate.presentationState {} else { require(false, "Blocked shortcut had no visible explanation") }
guide.close(finished: false)
settingsWindow.orderOut(nil)
if let item = delegate.statusItem { NSStatusBar.system.removeStatusItem(item) }
print("PASS: actual app settings/menu wiring, delivered-sentence observation, ready-state guard and capture exclusion")
