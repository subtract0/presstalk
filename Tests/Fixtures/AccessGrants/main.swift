import AppKit
import Foundation
import PressTalkCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}
require(CommandLine.arguments.count == 3, "Provide the live extension and permanent licence files")
let extensionKey = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let permanentKey = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let domain = "com.am.presstalk.access-grants-test.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
final class ExpiredAnchor: TrialAnchorStore {
    let name = "isolated-expired-trial"
    var writes = 0
    func read() -> TrialAnchor.Reading { .found(Date().addingTimeInterval(-30 * 86400)) }
    func write(_ date: Date) -> Bool { writes += 1; return false }
}
let anchor = ExpiredAnchor()
defaults.set(false, forKey: "PressTalk.PredatesPaidLicensing")
let store = PressTalkLicenseStore(defaults: defaults, env: [:], anchorStores: [anchor])
require(store.shouldBlockDictation, "Fixture did not begin with an expired trial")
let extensionLicense = try store.importLicense(extensionKey).get()
require(extensionLicense.expiresAt != nil, "Expected a signed temporary extension")
require(!store.shouldBlockDictation && store.currentPlanName == "Extended trial", "Live extension did not restore native access")
require(store.planSummary.contains("Free dictation until") && !store.planSummary.contains("future Mac update"), "Temporary access is described as permanent")
let settings = JarvisTapSettingsStore(config: JarvisTapConfig.load(), defaults: defaults)
let controller = PressTalkSettingsWindowController(settingsStore: settings, licenseStore: store, audioInputDefaults: defaults)
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let buy = descendants(controller.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Buy PressTalk" }!
require(!buy.isHidden, "Extended trial hides the option to buy permanent access")
let reloaded = PressTalkLicenseStore(defaults: UserDefaults(suiteName: domain)!, env: [:], anchorStores: [anchor])
require(!reloaded.shouldBlockDictation && reloaded.currentPlanName == "Extended trial", "Extension lost after store restart")
_ = try store.importLicense(permanentKey).get()
controller.reloadFromStore()
require(!store.shouldBlockDictation && buy.isHidden, "Permanent upgrade did not update the real Settings view")
if case .failure(.existingLicenseIsBetter) = store.importLicense(extensionKey) {} else { fatalError("Temporary key displaced permanent access") }
require(store.currentPlanName == "Founder", "Permanent licence not retained")
require(anchor.writes == 0, "Import rewrote the original trial anchor")
require(!controller.window!.isVisible, "Probe unexpectedly showed a window")
print("PASS: live service keys restore an expired native trial, persist, show correct Settings actions and preserve a permanent licence without touching owner preferences or Keychain")
