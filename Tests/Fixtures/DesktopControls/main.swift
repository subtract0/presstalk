import AppKit
import Foundation

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
