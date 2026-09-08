import AppKit
import Foundation
import PressTalkCore

// Exercise the shipped window and actions, without showing a window, changing
// a permission or reading the real licence/Keychain stores.
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let domain = "com.am.presstalk.desktop-controls-test.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
let config = JarvisTapConfig.load()
require(!config.allowPermissionPaneOpen, "Fixture must reproduce the managed launch")
let settings = JarvisTapSettingsStore(config: config, defaults: defaults)
let licence = PressTalkLicenseStore(defaults: defaults, env: [:], anchorStores: [])
let controller = PressTalkSettingsWindowController(settingsStore: settings, licenseStore: licence)
controller.updateRuntimeStatus(.placeholder) // automatic prompts disabled, permissions missing

func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}
let buttons = descendants(controller.window!.contentView!).compactMap { $0 as? NSButton }
var microphoneClicks = 0, accessibilityClicks = 0, inputClicks = 0
controller.onOpenMicrophoneSettings = { microphoneClicks += 1 }
controller.onOpenAccessibilitySettings = { accessibilityClicks += 1 }
controller.onOpenInputMonitoringSettings = { inputClicks += 1 }
for title in ["Microphone", "Accessibility", "Input Monitoring"] {
    guard let button = buttons.first(where: { $0.title == title }) else {
        fatalError("Missing real Settings button: \(title)")
    }
    require(!button.isHiddenOrHasHiddenAncestor && button.isEnabled,
                 "Managed launch made explicit \(title) action unreachable")
    button.performClick(nil)
}
require(microphoneClicks == 1 && accessibilityClicks == 1 && inputClicks == 1,
             "A visible permission button did not invoke its production action")
require(!controller.window!.isVisible, "Test must never show the window")
print("PASS: managed-launch Settings buttons are reachable and all three real actions fire")

// Exercise the actual app store call sites as well as the core policy. These
// stores deliberately count every access; no real Keychain record is touched.
final class CountingAnchor: TrialAnchorStore {
    let name = "counting-test-store"
    var reads = 0
    var writes = 0
    var reading: TrialAnchor.Reading = .absent
    func read() -> TrialAnchor.Reading { reads += 1; return reading }
    func write(_ date: Date) -> Bool { writes += 1; return true }
}
for earlyUser in [false, true] {
    defaults.set(earlyUser, forKey: "PressTalk.PredatesPaidLicensing")
    let anchor = CountingAnchor()
    let owner = PressTalkLicenseStore(defaults: defaults,
        env: earlyUser ? [:] : ["PRESSTALK_ENTITLEMENT_OVERRIDE": "founder"],
        anchorStores: [anchor])
    require(owner.state.allowsDictation, "Owner lost dictation access")
    require(!owner.shouldBlockDictation, "Owner was blocked by the trial")
    owner.startTrialIfNeeded()
    require(anchor.reads == 0 && anchor.writes == 0,
        "The production owner path accessed the trial anchor")
}
defaults.set(false, forKey: "PressTalk.PredatesPaidLicensing")
let trialAnchor = CountingAnchor()
let trial = PressTalkLicenseStore(defaults: defaults, env: [:], anchorStores: [trialAnchor])
require(trial.state.allowsDictation, "Fresh trial cannot dictate")
trial.startTrialIfNeeded()
require(trialAnchor.reads > 0 && trialAnchor.writes == 1,
    "Production trial handling no longer reads and starts its anchor")
let expiredAnchor = CountingAnchor()
expiredAnchor.reading = .found(Date().addingTimeInterval(-10 * 86400))
let expired = PressTalkLicenseStore(defaults: defaults, env: [:], anchorStores: [expiredAnchor])
require(expired.state == .trialExpired,
    "The production state call site no longer supplies the real trial anchor")
print("PASS: production owners skip trial stores; actual trials still read and start their anchor")
