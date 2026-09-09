import AppKit
import Foundation
import PressTalkCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func spin(until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(2)
    while !condition() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let guide = FirstRunSetupWindowController()
var microphone = false, shortcut = false, accessibility = false, model = false, dictated = false
var needsAccessibility = true
var details = FirstRunSetupWindowController.Details()
details.triggerName = "Fn"
details.microphoneName = "Shure MV7i"
details.microphoneAuthorization = "authorized"
guide.onReadConditions = {
    .init(microphoneCaptureVerified: microphone, inputMonitoringGranted: shortcut,
        accessibilityGranted: accessibility, speechModelReady: model,
        firstDictationDelivered: dictated, triggerRequiresInputMonitoring: true,
        triggerRequiresAccessibility: needsAccessibility)
}
guide.onReadDetails = { details }
let content = guide.window!.contentView!
let primary = descendants(content).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "setup.primary" }!
let skip = descendants(content).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "setup.skip" }!
func text(_ identifier: String) -> String {
    descendants(content).compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == identifier }!.stringValue
}
var probeCalls = 0
var probeCompletion: ((AudioCaptureProbeReport) -> Void)?
guide.onVerifyMicrophone = { completion in probeCalls += 1; probeCompletion = completion }
func report(_ outcome: AudioCaptureProbeReport.Outcome, frames: Int = 0) -> AudioCaptureProbeReport {
    .init(outcome: outcome, authorizationStatus: "authorized", sampleRate: 16000,
        channelCount: 1, framesCaptured: frames, peakAmplitude: 0.05,
        durationSeconds: 1.2, detail: "Microphone disconnected during check")
}
guide.refresh()
require(primary.title == "Test microphone", "Already-authorized mic still asks for permission")
primary.performClick(nil)
require(probeCalls == 1, "Real microphone button did not invoke its capture action")
require(!primary.isEnabled && primary.title.contains("Checking"), "No visible in-progress state")
require(text("setup.detail").contains("Speak normally"), "No instruction during microphone check")
primary.performClick(nil)
require(probeCalls == 1, "Repeated clicks started concurrent checks")
probeCompletion!(report(.engineFailed)); spin(until: { primary.isEnabled })
require(primary.isEnabled && text("setup.step") == "Microphone", "Failed capture advanced setup")
require(text("setup.detail").contains("disconnected"), "Capture error was hidden")
var permissionClicks = 0
guide.onOpenMicrophoneSettings = { permissionClicks += 1 }
details.microphoneAuthorization = "denied"; guide.refresh()
primary.performClick(nil)
require(text("setup.detail").contains("access is off"), "Denied access showed a stale success")
require(permissionClicks == 1 && probeCalls == 1, "Denied mic did not open the correct settings action")
details.microphoneAuthorization = "authorized"
details.recordingOrProcessing = true; guide.refresh()
require(!primary.isEnabled && text("setup.detail").contains("Finish"), "Check can interrupt a dictation")
details.recordingOrProcessing = false; guide.refresh()
primary.performClick(nil)
microphone = true; probeCompletion!(report(.captured, frames: 19200))
spin(until: { primary.isEnabled && text("setup.step") != "Microphone" })
require(text("setup.step") == "Pasting into apps", "Successful mic did not advance to permission")
require(skip.isHidden, "Fn setup offers an impossible Accessibility skip")
var accessibilityClicks = 0
guide.onOpenAccessibilitySettings = { accessibilityClicks += 1 }
primary.performClick(nil)
require(accessibilityClicks == 1, "Accessibility action is disconnected")
accessibility = true; guide.refresh()
require(text("setup.step") == "Trigger key", "Permission return did not update the step")
var inputClicks = 0
guide.onOpenInputMonitoringSettings = { inputClicks += 1 }
primary.performClick(nil)
require(inputClicks == 1, "Shortcut settings action is disconnected")
// A registered Option-Space shortcut does not need Input Monitoring.
details.shortcutUsesRegisteredHotKey = true
var shortcutRetries = 0
guide.onRetryShortcut = { shortcutRetries += 1; return false }
guide.refresh(); primary.performClick(nil)
require(shortcutRetries == 1 && inputClicks == 1, "Registered shortcut opened an irrelevant permission pane")
require(text("setup.detail").contains("still unavailable"), "Failed shortcut retry gave no feedback")
details.shortcutUsesRegisteredHotKey = false
shortcut = true
var modelStarts = 0
guide.onDownloadSpeechModel = {
    modelStarts += 1
    details.modelState = .loading
    details.modelStatus = "Downloading speech model. Keep your Mac connected."
}
guide.refresh(); primary.performClick(nil)
require(modelStarts == 1 && !primary.isEnabled, "Model button does not start or show preparation")
require(text("setup.detail").contains("Downloading"), "Model progress missing")
details.modelState = .failed
details.modelStatus = "Download interrupted. Check your internet connection and try again."
guide.refresh()
require(primary.isEnabled && primary.title == "Retry speech model", "Failed model has no retry")
primary.performClick(nil)
require(modelStarts == 2, "Model retry button does nothing")
model = true; details.modelState = .ready; guide.refresh()
require(text("setup.step") == "Your first dictation", "Model ready did not advance")
primary.performClick(nil)
let practice = descendants(content).compactMap { $0 as? NSTextView }.first { $0.accessibilityIdentifier() == "setup.practice" }!
require(guide.window!.firstResponder === practice, "Try dictation button did not focus an editable field")
practice.string = "Typed text must not count as a completed dictation."
guide.refresh()
require(text("setup.step") == "Your first dictation", "Typing was counted as successful dictation")
guide.onConfirmDictation = { dictated = true }
guide.beginDictation()
guide.observeDictation(practice.string)
require(!dictated, "Pre-existing text was counted as a delivered dictation")
practice.string = "The whole sentence must arrive here. "
practice.setSelectedRange(NSRange(location: (practice.string as NSString).length, length: 0))
guide.beginDictation()
guide.observeDictation("The whole sentence must arrive here.")
practice.string += "The whole sentence"
guide.refresh()
require(!dictated, "An old complete sentence concealed a truncated new insertion")
// Replacing selected text is also a valid insertion, including shared words.
practice.string = "The whole sentence was here before."
practice.setSelectedRange(NSRange(location: 0, length: (practice.string as NSString).length))
guide.beginDictation()
guide.observeDictation("The whole sentence must arrive here.")
practice.string = "The whole sentence"
guide.refresh()
require(!dictated, "A truncated sentence passed the practice check")
practice.string = "The whole sentence must arrive here. "
guide.refresh()
require(dictated, "A complete recognised sentence did not confirm delivery")
require(primary.title == "Done", "Delivered dictation did not finish check")
require(text("setup.progress") == "5 of 5 checks complete", "Completion progress wrong")
var finishes = 0
guide.onFinish = { finishes += 1 }
guide.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: guide.window))
require(finishes == 0, "Closing the window falsely completed setup")
primary.performClick(nil)
require(finishes == 1, "Done button did not persist completed setup")
// A shortcut that really works without Accessibility can use the clipboard.
needsAccessibility = false; accessibility = false; dictated = false; guide.refresh()
require(!skip.isHidden, "Clipboard-only setup cannot continue")
skip.performClick(nil)
require(text("setup.step") == "Your first dictation", "Clipboard choice did not advance")
dictated = true; guide.refresh()
require(text("setup.progress") == "5 of 5 checks complete", "Skipped optional check left progress incomplete")
require(!guide.window!.isVisible, "Interaction test unexpectedly displayed a window")

// Render the real views, at the minimum supported size, into a local artifact.
if let directory = ProcessInfo.processInfo.environment["PRESSTALK_UI_ARTIFACTS"] {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    func snapshot(_ name: String) {
        guide.window!.setContentSize(NSSize(width: 520, height: 500))
        content.layoutSubtreeIfNeeded()
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            // Offscreen AppKit views omit the window's opaque background.
            // Composite that background explicitly, as the window server does.
            let rendered = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rendered)
            let context = NSGraphicsContext.current!.cgContext
            let rect = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(rect)
            context.setBlendMode(.normal)
            context.draw(bitmap.cgImage!, in: rect)
            NSGraphicsContext.restoreGraphicsState()
            if let png = rendered.representation(using: .png, properties: [:]) {
                try! png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            }
        }
    }
    dictated = false; accessibility = true; needsAccessibility = true
    details.pasteAutomatically = true; details.triggerName = "Fn"
    guide.beginDictation(); guide.refresh(); snapshot("setup-dictation")
    microphone = false; details.microphoneAuthorization = "denied"; guide.refresh(); snapshot("setup-microphone-denied")
    microphone = true; model = false; details.modelState = .failed
    details.modelStatus = String(repeating: "Model download interrupted. Check the connection and retry. ", count: 5)
    guide.refresh(); snapshot("setup-model-failed-long-message")
}
print("PASS: real setup controls handle busy, denied, failed, retry, skip, dictation and close states")
