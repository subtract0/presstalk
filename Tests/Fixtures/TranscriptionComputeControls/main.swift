import AppKit
import Foundation
import PressTalkCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}
func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let domain = "com.am.presstalk.compute-controls-test.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
let config = JarvisTapConfig.load()
let settings = JarvisTapSettingsStore(config: config, defaults: defaults)
// Empty stores prevent any access to the real Keychain or trial anchors.
let licence = PressTalkLicenseStore(defaults: defaults, env: [:], anchorStores: [])
let controller = PressTalkSettingsWindowController(
    settingsStore: settings, licenseStore: licence, audioInputDefaults: defaults)

func popup(in controller: PressTalkSettingsWindowController) -> NSPopUpButton {
    guard let popup = descendants(controller.window!.contentView!)
        .compactMap({ $0 as? NSPopUpButton })
        .first(where: { $0.accessibilityIdentifier() == "settings.transcriptionCompute" })
    else { fatalError("Missing native transcription processor setting") }
    return popup
}
func choose(_ device: TranscriptionComputeDevice, in popup: NSPopUpButton) {
    popup.selectItem(at: TranscriptionComputeDevice.allCases.firstIndex(of: device)!)
    app.sendAction(popup.action!, to: popup.target, from: popup)
}

let picker = popup(in: controller)
require(!picker.isHiddenOrHasHiddenAncestor && picker.isEnabled,
        "Processor choice is unreachable")
require(picker.itemTitles == ["Apple Neural Engine", "GPU"],
        "Processor choices are missing or a hidden automatic mode was added")
require(settings.transcriptionComputeDevice == .neuralEngine &&
        picker.titleOfSelectedItem == "Apple Neural Engine",
        "Fresh settings no longer use the released ANE default")

var changes = 0
controller.onTranscriptionComputeChanged = { changes += 1 }
choose(.gpu, in: picker)
require(changes == 1, "GPU selection did not invoke the compute-change callback")
require(settings.transcriptionComputeDevice == .gpu &&
        defaults.string(forKey: TranscriptionComputeDevice.preferenceKey) == "gpu",
        "GPU selection was not saved before notifying the app")

let reloadedDefaults = UserDefaults(suiteName: domain)!
let reloadedSettings = JarvisTapSettingsStore(config: config, defaults: reloadedDefaults)
require(reloadedSettings.transcriptionComputeDevice == .gpu,
        "A new settings store lost the saved GPU choice")
let reopened = PressTalkSettingsWindowController(
    settingsStore: reloadedSettings, licenseStore: licence, audioInputDefaults: reloadedDefaults)
let reopenedPicker = popup(in: reopened)
require(reopenedPicker.titleOfSelectedItem == "GPU",
        "Reopened Settings disagrees with the persisted processor")
var reopenedChanges = 0
reopened.onTranscriptionComputeChanged = { reopenedChanges += 1 }
choose(.neuralEngine, in: reopenedPicker)
require(reopenedChanges == 1 && reloadedSettings.transcriptionComputeDevice == .neuralEngine,
        "Switching back to ANE lost its action or preference")
require(JarvisTapSettingsStore(config: config, defaults: UserDefaults(suiteName: domain)!)
        .transcriptionComputeDevice == .neuralEngine,
        "ANE choice did not survive another store recreation")

// Runtime recovery may restore the previous device after a loading failure.
// Refreshing the actual UI must reflect that restoration without a reload loop.
settings.transcriptionComputeDevice = .gpu
controller.reloadFromStore()
require(picker.titleOfSelectedItem == "GPU" && changes == 1,
        "Refreshing the saved choice invoked another model change")

picker.select(nil)
app.sendAction(picker.action!, to: picker.target, from: picker)
require(settings.transcriptionComputeDevice == .gpu && changes == 1,
        "An empty menu selection changed the processor")

defaults.set("unsupported-legacy-mode", forKey: TranscriptionComputeDevice.preferenceKey)
controller.reloadFromStore()
require(settings.transcriptionComputeDevice == .neuralEngine &&
        picker.titleOfSelectedItem == "Apple Neural Engine",
        "Malformed saved preferences do not recover to the ANE default")
require(!controller.window!.isVisible && !reopened.window!.isVisible,
        "Fixture unexpectedly opened a user-facing window")
if let renderDirectory = ProcessInfo.processInfo.environment["PRESSTALK_COMPUTE_RENDER_DIR"] {
    let output = URL(fileURLWithPath: renderDirectory, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    settings.transcriptionComputeDevice = .gpu
    controller.reloadFromStore()
    controller.window!.appearance = NSAppearance(named: .darkAqua)
    app.finishLaunching()
    for (name, size) in [
        ("settings-default", NSSize(width: 560, height: 620)),
        ("settings-minimum", controller.window!.contentRect(
            forFrameRect: NSRect(origin: .zero, size: controller.window!.minSize)).size),
    ] {
        controller.window!.setContentSize(size)
        let content = controller.window!.contentView!
        content.layoutSubtreeIfNeeded()
        controller.window!.displayIfNeeded()
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
        controller.window!.appearance!.performAsCurrentDrawingAppearance {
            content.cacheDisplay(in: content.bounds, to: bitmap)
        }
        let pickerRect = picker.convert(picker.bounds, to: content)
        require(content.bounds.contains(pickerRect), "Processor control is clipped at \(name)")
        // Hidden windows do not paint the native window backing into the view
        // snapshot. Composite that exact AppKit background to preserve alpha.
        let rendered = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rendered)!
        controller.window!.appearance!.performAsCurrentDrawingAppearance {
            controller.window!.backgroundColor.setFill()
            NSBezierPath(rect: content.bounds).fill()
            NSGraphicsContext.current!.cgContext.setBlendMode(.normal)
            NSGraphicsContext.current!.cgContext.draw(bitmap.cgImage!, in: content.bounds)
        }
        NSGraphicsContext.restoreGraphicsState()
        let data = rendered.representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent(name + ".png"))
    }
    require(!controller.window!.isVisible, "Offscreen render showed the Settings window")
}
print("PASS: native ANE/GPU choice, callbacks, persistence, recovery refresh and invalid selection")
