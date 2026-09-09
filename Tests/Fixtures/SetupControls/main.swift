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
details.shortcutID = "fn"
details.shortcutChoices = [.init(id: "fn", title: "Fn / Globe"),
    .init(id: "option_space", title: "Option + Space"), .init(id: "f5", title: "F5 / Mic")]
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
require(text("setup.detail").contains("Waiting for you to click"), "Idle setup looks like background work")
require(descendants(content).allSatisfy { !($0 is NSProgressIndicator) }, "Idle setup still shows a loading-style progress bar")
let shortcutPicker = descendants(content).compactMap { $0 as? NSPopUpButton }
    .first { $0.accessibilityIdentifier() == "setup.shortcut" }!
var shortcutChanges: [String] = []
guide.onChangeShortcut = { value in
    shortcutChanges.append(value); details.shortcutID = value
    details.triggerName = details.shortcutChoices.first { $0.id == value }!.title
    return true
}
shortcutPicker.selectItem(at: 2)
app.sendAction(shortcutPicker.action!, to: shortcutPicker.target, from: shortcutPicker)
require(shortcutChanges == ["f5"] && details.triggerName == "F5 / Mic", "Setup shortcut selection did not call its production action")
primary.performClick(nil)
require(probeCalls == 1, "Real microphone button did not invoke its capture action")
require(!primary.isEnabled && primary.title.contains("Checking"), "No visible in-progress state")
require(!shortcutPicker.isEnabled, "Shortcut can change during microphone test")
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
require(text("setup.detail").contains("Waiting for you to hold F5 / Mic"), "Practice instructions ignore the chosen shortcut")
details.recordingOrProcessing = true; details.isRecording = true; guide.refresh()
require(primary.title == "Listening…" && !primary.isEnabled && !shortcutPicker.isEnabled,
    "Recording does not show clear listening state or lock shortcut changes")
shortcutPicker.selectItem(at: 0)
app.sendAction(shortcutPicker.action!, to: shortcutPicker.target, from: shortcutPicker)
require(shortcutChanges == ["f5"], "An action bypassed the busy shortcut guard")
details.isRecording = false; guide.refresh()
require(primary.title == "Recognising…", "Processing looks like idle input")
details.recordingOrProcessing = false; guide.refresh()
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
    func snapshot(_ name: String, appearance: NSAppearance.Name = .aqua) {
        app.setActivationPolicy(.accessory)
        guide.window!.appearance = NSAppearance(named: appearance)
        guide.window!.setContentSize(NSSize(width: 520, height: 500))
        guide.window!.orderBack(nil)
        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        guide.window!.displayIfNeeded()
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-o", "-x", "-l", String(guide.window!.windowNumber),
            URL(fileURLWithPath: directory).appendingPathComponent(name + ".png").path]
        try! capture.run(); capture.waitUntilExit()
        require(capture.terminationStatus == 0, "Native setup screenshot failed")
        guide.window!.orderOut(nil)
        app.setActivationPolicy(.prohibited)
    }
    dictated = false; accessibility = true; needsAccessibility = true
    details.pasteAutomatically = true; details.triggerName = "F5 / Mic"
    details.shortcutID = "f5"; practice.string = ""
    guide.beginDictation(); guide.refresh(); snapshot("setup-dictation")
    snapshot("setup-dictation-dark", appearance: .darkAqua)
    microphone = false; details.microphoneAuthorization = "authorized"; guide.refresh(); snapshot("setup-microphone-waiting")
    details.microphoneAuthorization = "denied"; guide.refresh(); snapshot("setup-microphone-denied")
    microphone = true; model = false; details.modelState = .failed
    details.modelStatus = String(repeating: "Model download interrupted. Check the connection and retry. ", count: 5)
    guide.refresh(); snapshot("setup-model-failed-long-message")
}
print("PASS: real setup controls handle busy, denied, failed, retry, skip, dictation and close states")
