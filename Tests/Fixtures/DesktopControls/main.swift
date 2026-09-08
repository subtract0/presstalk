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
let controller = PressTalkSettingsWindowController(settingsStore: settings, licenseStore: licence,
    audioInputDefaults: defaults)
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

func control<T: NSView>(_ identifier: String, as type: T.Type) -> T {
    guard let view = descendants(controller.window!.contentView!).compactMap({ $0 as? T })
        .first(where: { $0.accessibilityIdentifier() == identifier }) else {
        fatalError("Missing control: \(identifier)")
    }
    return view
}
var settingsChanges = 0
controller.onSettingsChanged = { settingsChanges += 1 }
let hud = control("settings.showHUD", as: NSButton.self)
let oldHUD = settings.showHUD
hud.performClick(nil)
require(settings.showHUD != oldHUD && settingsChanges == 1, "HUD toggle is disconnected")
let paste = control("settings.autoPaste", as: NSButton.self)
let oldPaste = settings.pasteAutomatically
paste.performClick(nil)
require(settings.pasteAutomatically != oldPaste && settingsChanges == 2, "Auto-paste toggle is disconnected")
let trigger = control("settings.trigger", as: NSPopUpButton.self)
let optionSpaceIndex = JarvisTapSettingsStore.TriggerKeyOption.allCases.firstIndex(of: .optionSpace)!
trigger.selectItem(at: optionSpaceIndex)
app.sendAction(trigger.action!, to: trigger.target, from: trigger)
require(settings.triggerKey == .optionSpace && settingsChanges == 3, "Shortcut picker did not persist selection")
let suffix = control("settings.insertionSuffix", as: NSPopUpButton.self)
let suffixIndex = (suffix.indexOfSelectedItem + 1) % suffix.numberOfItems
suffix.selectItem(at: suffixIndex)
app.sendAction(suffix.action!, to: suffix.target, from: suffix)
require(settings.insertionSuffix == JarvisTapSettingsStore.InsertionSuffixOption.allCases[suffixIndex], "Insertion suffix selection was lost")
let tail = control("settings.releaseTail", as: NSSlider.self)
tail.doubleValue = 0.43
app.sendAction(tail.action!, to: tail.target, from: tail)
require(abs(settings.releaseTailMaxSeconds - 0.45) < 0.001, "Release tail control did not persist its rounded value")
var checks = 0, dictationChecks = 0, exports = 0, restarts = 0
controller.onRunSetupCheck = { checks += 1 }
controller.onRunPhysicalSmoke = { dictationChecks += 1 }
controller.onExportDiagnostics = { exports += 1 }
controller.onRestartApp = { restarts += 1 }
for title in ["Run Setup Check", "Test Dictation Shortcut", "Export Diagnostics", "Restart PressTalk"] {
    guard let button = buttons.first(where: { $0.title == title }) else { fatalError("Missing action: \(title)") }
    require(!button.isHiddenOrHasHiddenAncestor && button.isEnabled, "Action is unreachable: \(title)")
    button.performClick(nil)
}
require(checks == 1 && dictationChecks == 1 && exports == 1 && restarts == 1, "A settings action did nothing")

// Use isolated preferences while testing the real microphone picker. A UID
// must survive reordered IDs, disconnection, and reopening the popup.
var devices: [PressTalkSettingsWindowController.AudioInputChoice] = [
    .init(uid: "test-shure", name: "Shure MV7i", isDefault: false, isBluetooth: false, startNote: nil),
    .init(uid: "test-airpods", name: "AirPods", isDefault: true, isBluetooth: true, startNote: nil),
]
controller.onListAudioInputs = { devices }
defaults.set(AudioInputPreference.specificDevice(uid: "test-shure").storageValue,
    forKey: "PressTalk.AudioInputPreference")
controller.rebuildMicrophoneMenu()
let mic = control("settings.microphone", as: NSPopUpButton.self)
require(mic.titleOfSelectedItem == "Shure MV7i", "Saved microphone selection changed")
devices.reverse(); controller.rebuildMicrophoneMenu()
require(mic.titleOfSelectedItem == "Shure MV7i", "Enumeration reorder changed the chosen microphone")
devices.removeAll { $0.uid == "test-shure" }; controller.rebuildMicrophoneMenu()
require(mic.titleOfSelectedItem?.contains("not connected") == true, "Missing microphone silently selected another device")
var micChanges = 0
controller.onAudioInputPreferenceChanged = { micChanges += 1 }
defaults.set("test-shure", forKey: "PressTalk.AudioInputAvoidUID")
mic.selectItem(at: 0); app.sendAction(mic.action!, to: mic.target, from: mic)
require(AudioInputPreference(storageValue: defaults.string(forKey: "PressTalk.AudioInputPreference")) == .systemDefault,
    "System default choice did not persist in the app preferences")
require(micChanges == 1 && defaults.object(forKey: "PressTalk.AudioInputAvoidUID") == nil,
    "Microphone selection callback or retry decision was lost")

// A real downloaded test-purchase licence can be checked without changing the
// owner's preferences or reading any real Keychain anchor.
if let path = ProcessInfo.processInfo.environment["PRESSTALK_ACCEPTANCE_LICENSE_FILE"] {
    let encoded = try String(contentsOfFile: path, encoding: .utf8)
    defaults.set(false, forKey: "PressTalk.PredatesPaidLicensing")
    let expired = CountingAnchor()
    expired.reading = .found(Date().addingTimeInterval(-30 * 86400))
    let paid = PressTalkLicenseStore(defaults: defaults, env: [:], anchorStores: [expired])
    if case .failure(let error) = paid.importLicense(encoded) { fatalError("Delivered licence failed native verifier: \(error)") }
    require(paid.currentPlanName == "Founder" && !paid.shouldBlockDictation, "Purchase did not override expired trial")
    let relaunched = PressTalkLicenseStore(defaults: UserDefaults(suiteName: domain)!, env: [:], anchorStores: [expired])
    require(relaunched.currentPlanName == "Founder" && !relaunched.shouldBlockDictation,
        "A fresh native licence store could not recover the saved purchase")
    if case .success = relaunched.importLicense("invalid") { fatalError("Invalid licence was accepted") }
    require(relaunched.currentPlanName == "Founder", "A bad import destroyed a working licence")
    require(expired.reads == 0 && expired.writes == 0, "Paid store unnecessarily accessed the trial anchors")
    controller.reloadFromStore()
    let buy = buttons.first { $0.title == "Buy PressTalk" }!
    require(buy.isHidden, "Activated customer still sees a misleading upgrade offer")
    require(descendants(controller.window!.contentView!).compactMap { $0 as? NSTextField }
        .contains { $0.stringValue == "Founder" }, "Settings does not show the activated licence")
}
controller.window!.setContentSize(NSSize(width: 520, height: 420))
controller.window!.contentView!.layoutSubtreeIfNeeded()
require(!controller.window!.isVisible, "Controls test unexpectedly opened a window")
print("PASS: settings changes persist, actions fire, mic choice survives reconnects, and native paid licence survives store restart")
