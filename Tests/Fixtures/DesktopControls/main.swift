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
#if DEBUG
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
#else
// Compile this fixture without DEBUG as well as with it. A process environment
// value must not unlock the actual release store after its trial has expired.
defaults.set(false, forKey: "PressTalk.PredatesPaidLicensing")
let releaseAnchor = CountingAnchor()
releaseAnchor.reading = .found(Date().addingTimeInterval(-10 * 86400))
let unlicensedRelease = PressTalkLicenseStore(defaults: defaults,
    env: ["PRESSTALK_ENTITLEMENT_OVERRIDE": "founder"], anchorStores: [releaseAnchor])
require(unlicensedRelease.state == .trialExpired && unlicensedRelease.shouldBlockDictation,
    "A release build accepted an unverified entitlement override")
unlicensedRelease.startTrialIfNeeded()
require(releaseAnchor.reads > 0 && releaseAnchor.writes == 0,
    "Release enforcement reset an existing expired trial")

defaults.set(true, forKey: "PressTalk.PredatesPaidLicensing")
let earlyAnchor = CountingAnchor()
earlyAnchor.reading = .unavailable
let earlyRelease = PressTalkLicenseStore(defaults: defaults,
    env: ["PRESSTALK_ENTITLEMENT_OVERRIDE": "founder"], anchorStores: [earlyAnchor])
require(earlyRelease.state == .grandfathered && !earlyRelease.shouldBlockDictation,
    "Ignoring a release override removed or replaced an early user's entitlement")
earlyRelease.startTrialIfNeeded()
require(earlyAnchor.reads == 0 && earlyAnchor.writes == 0,
    "A release build accessed trial storage for an early user")
print("PASS: release ignores unverified entitlement overrides and preserves early-user access")
#endif
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
print("PASS: actual trials still read and start their anchor")

func control<T: NSView>(_ identifier: String, as type: T.Type) -> T {
    guard let view = descendants(controller.window!.contentView!).compactMap({ $0 as? T })
        .first(where: { $0.accessibilityIdentifier() == identifier }) else {
        fatalError("Missing control: \(identifier)")
    }
    return view
}

// Exercise the real updater controls against an isolated preference provider.
// Refreshes must only read preferences: opting out cannot silently opt back in.
var updateSettings = PressTalkSettingsWindowController.UpdateSettings(
    available: true, canCheck: true, automaticChecks: true, automaticDownloads: true,
    message: "Updates are ready.")
var updateChecks = 0
var checkPreferenceWrites: [Bool] = []
var downloadPreferenceWrites: [Bool] = []
controller.onReadUpdateSettings = { updateSettings }
controller.onCheckForUpdates = { updateChecks += 1 }
controller.onAutomaticUpdateChecksChanged = {
    checkPreferenceWrites.append($0)
    updateSettings.automaticChecks = $0
}
controller.onAutomaticUpdateDownloadsChanged = {
    downloadPreferenceWrites.append($0)
    updateSettings.automaticDownloads = $0
}
let checkUpdate = control("settings.checkForUpdates", as: NSButton.self)
let automaticChecks = control("settings.automaticUpdateChecks", as: NSButton.self)
let automaticDownloads = control("settings.automaticUpdateDownloads", as: NSButton.self)
controller.refreshUpdateSettings()
require(checkUpdate.isEnabled && automaticChecks.isEnabled && automaticDownloads.isEnabled,
    "Official release update controls are unreachable")
checkUpdate.performClick(nil)
require(updateChecks == 1, "Check for Updates did not invoke its production callback")
automaticDownloads.performClick(nil)
require(downloadPreferenceWrites == [false] && !updateSettings.automaticDownloads,
    "Automatic download opt-out was not saved exactly once")
automaticChecks.performClick(nil)
require(checkPreferenceWrites == [false] && !updateSettings.automaticChecks,
    "Automatic check opt-out was not saved exactly once")
require(!automaticDownloads.isEnabled, "Downloads remain interactive while automatic checks are off")
app.sendAction(automaticDownloads.action!, to: automaticDownloads.target, from: automaticDownloads)
require(downloadPreferenceWrites == [false], "Disabled download action bypassed its availability guard")
for _ in 0..<3 {
    controller.refreshUpdateSettings()
    controller.reloadFromStore()
    controller.updateRuntimeStatus(.placeholder)
}
require(automaticChecks.state == .off && automaticDownloads.state == .off,
    "Refreshing Settings overwrote the update opt-outs")
require(checkPreferenceWrites == [false] && downloadPreferenceWrites == [false],
    "Refreshing Settings recursively wrote update preferences")
automaticChecks.performClick(nil)
automaticDownloads.performClick(nil)
require(checkPreferenceWrites == [false, true] && downloadPreferenceWrites == [false, true],
    "Automatic update controls cannot opt back in")

updateSettings.canCheck = false
controller.refreshUpdateSettings()
require(!checkUpdate.isEnabled, "Busy updater still offers a manual check")
app.sendAction(checkUpdate.action!, to: checkUpdate.target, from: checkUpdate)
require(updateChecks == 1, "Busy updater action bypassed its availability guard")
updateSettings.available = false
updateSettings.canCheck = true
controller.refreshUpdateSettings()
require(!checkUpdate.isEnabled && !automaticChecks.isEnabled && !automaticDownloads.isEnabled,
    "Development app exposes working production-update controls")
for button in [checkUpdate, automaticChecks, automaticDownloads] {
    app.sendAction(button.action!, to: button.target, from: button)
}
require(updateChecks == 1 && checkPreferenceWrites == [false, true]
    && downloadPreferenceWrites == [false, true], "Unavailable updater action reached a callback")
print("PASS: update controls fire, preserve opt-outs on refresh, avoid recursive writes and disable unavailable actions")

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
    paid.startTrialIfNeeded()
    let relaunched = PressTalkLicenseStore(defaults: UserDefaults(suiteName: domain)!, env: [:], anchorStores: [expired])
    require(relaunched.currentPlanName == "Founder" && !relaunched.shouldBlockDictation,
        "A fresh native licence store could not recover the saved purchase")
    relaunched.startTrialIfNeeded()
    if case .success = relaunched.importLicense("invalid") { fatalError("Invalid licence was accepted") }
    require(relaunched.currentPlanName == "Founder", "A bad import destroyed a working licence")
    require(expired.reads == 0 && expired.writes == 0, "Paid store unnecessarily accessed the trial anchors")
    controller.reloadFromStore()
    let buy = buttons.first { $0.title == "Buy PressTalk" }!
    require(buy.isHidden, "Activated customer still sees a misleading upgrade offer")
    require(descendants(controller.window!.contentView!).compactMap { $0 as? NSTextField }
        .contains { $0.stringValue == "Founder" }, "Settings does not show the activated licence")
    print("PASS: delivered founder licence activates, survives store restart and skips trial storage")
} else {
    print("SKIP: delivered signed-licence acceptance; PRESSTALK_ACCEPTANCE_LICENSE_FILE is not set")
}
controller.window!.setContentSize(NSSize(width: 520, height: 420))
controller.window!.contentView!.layoutSubtreeIfNeeded()
require(!controller.window!.isVisible, "Controls test unexpectedly opened a window")
print("PASS: settings changes persist, actions fire and mic choice survives reconnects")
