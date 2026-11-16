import AppKit
import Foundation
import PressTalkCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func spin() {
    let deadline = Date().addingTimeInterval(0.06)
    while let event = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
        NSApp.sendEvent(event)
    }
}

final class MutableTrialAnchor: TrialAnchorStore {
    let name = "app-wiring-trial-anchor"
    var reading: TrialAnchor.Reading
    var reads = 0
    var writes: [Date] = []

    init(_ reading: TrialAnchor.Reading) { self.reading = reading }
    func read() -> TrialAnchor.Reading { reads += 1; return reading }
    func write(_ date: Date) -> Bool {
        writes.append(date)
        reading = .found(date)
        return true
    }
}

func assertTrialAnchorRecovery() {
    let domain = "com.am.presstalk.trial-delivery-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let delegate = JarvisTapApp()
    delegate.settingsStore = JarvisTapSettingsStore(config: delegate.config, defaults: defaults)
    let preferences = MutableTrialAnchor(.absent)
    let keychain = MutableTrialAnchor(.unavailable)
    delegate.licenseStore = PressTalkLicenseStore(defaults: defaults, env: [:],
        anchorStores: [preferences, keychain])
    delegate.licenseStore.recordInstallGenerationIfNeeded()

    // Reproduce a first dictation while Keychain cannot be read. Delivery may
    // complete, but neither store may be assigned a potentially later date.
    delegate.recordDelivery("First successful trial dictation.", reachedTargetApp: true)
    require(delegate.settingsStore.firstDictationDelivered, "First delivery was not recorded")
    require(preferences.writes.isEmpty && keychain.writes.isEmpty,
        "An unreadable anchor was overwritten when the first dictation arrived")
    require(!delegate.licenseStore.shouldBlockDictation, "Unreadable trial storage blocked dictation")
    delegate.recordDelivery("Storage is still unreadable.", reachedTargetApp: true)
    require(preferences.writes.isEmpty && keychain.writes.isEmpty,
        "A retry wrote a trial date while storage remained unreadable")

    // The existing app incorrectly returned on firstDictationDelivered here,
    // leaving this installation with no trial date for all future dictations.
    keychain.reading = .absent
    delegate.recordDelivery("Storage can be read again.", reachedTargetApp: true)
    guard let startedAt = delegate.licenseStore.trialAnchor.startedAt else {
        fatalError("A delivered dictation did not start the deferred trial after storage recovered")
    }
    require(preferences.writes == [startedAt] && keychain.writes == [startedAt],
        "Recovered trial did not record the same start in both stores")
    require(delegate.licenseStore.state == .trial(daysRemaining: 3),
        "The recovered trial did not receive its normal duration")

    // Recreating the store models an app update/relaunch with the first-use
    // flag already persisted. Further deliveries must not restart the trial.
    delegate.licenseStore = PressTalkLicenseStore(defaults: defaults, env: [:],
        anchorStores: [preferences, keychain])
    delegate.licenseStore.recordInstallGenerationIfNeeded()
    delegate.recordDelivery("Another dictation after relaunch.", reachedTargetApp: true)
    require(delegate.licenseStore.trialAnchor.startedAt == startedAt
        && preferences.writes == [startedAt] && keychain.writes == [startedAt],
        "A later delivery or relaunch restarted an existing trial")
    require(delegate.licenseStore.currentPlanName == "Trial",
        "A later delivery or relaunch grandfathered a new installation")

    // An older surviving anchor must be healed, never replaced with today.
    let earlier = startedAt.addingTimeInterval(-86_400)
    preferences.reading = .absent
    keychain.reading = .found(earlier)
    delegate.recordDelivery("An existing date survives.", reachedTargetApp: true)
    require(delegate.licenseStore.trialAnchor.startedAt == earlier
        && preferences.writes.last == earlier && keychain.writes == [startedAt],
        "Retrying trial start moved an existing anchor forward")

    let expired = Date().addingTimeInterval(-4 * 86_400)
    preferences.reading = .found(expired)
    keychain.reading = .unavailable
    require(!delegate.licenseStore.shouldBlockDictation,
        "An expired trial was enforced while an anchor was unreadable")
    keychain.reading = .found(expired)
    require(delegate.licenseStore.shouldBlockDictation,
        "An expired trial was not enforced after storage recovered")

    // The new retry call must remain a no-op for early users and the existing
    // owner entitlement fixture; it must not introduce Keychain reads for them.
    for earlyUser in [true, false] {
        defaults.set(earlyUser, forKey: "PressTalk.PredatesPaidLicensing")
        let unused = MutableTrialAnchor(.unavailable)
        delegate.licenseStore = PressTalkLicenseStore(defaults: defaults,
            env: earlyUser ? [:] : ["PRESSTALK_ENTITLEMENT_OVERRIDE": "founder"],
            anchorStores: [unused])
        delegate.recordDelivery("Existing access remains available.", reachedTargetApp: true)
        require(!delegate.licenseStore.shouldBlockDictation
            && unused.reads == 0 && unused.writes.isEmpty,
            "A delivery touched trial storage for an existing owner or early user")
    }
    print("PASS: production delivery retries deferred trial start, preserves existing dates and owner access")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
func runAssertions() {
    assertTrialAnchorRecovery()
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
    delegate.installProductUI()
    let settingsWindow = delegate.settingsWindowController!.window!
    let buttons = descendants(settingsWindow.contentView!).compactMap { $0 as? NSButton }
    let setup = buttons.first { $0.accessibilityIdentifier() == "settings.runSetupCheck" }!
    setup.performClick(nil)
    guard let guide = delegate.firstRunSetupWindowController else { fatalError("Settings setup action never constructed the guide") }
    require(guide.window!.isVisible, "Settings setup action did not show a window")
    require(delegate.setupNeedsFreshDictation, "Setup accepted an old dictation as a fresh check")
    require(!delegate.inputPipelineReady && delegate.whisperWarmupTask == nil,
        "Setup check interrupted the busy dictation to start another pipeline")
    let originalShortcut = delegate.settingsStore.triggerKey
    require(guide.onChangeShortcut?("f5") == false && delegate.settingsStore.triggerKey == originalShortcut,
        "Setup changed the app shortcut during a dictation")
    // Keep the listener itself isolated: the fixture says F5 is already
    // installed, so this exercises production persistence/refresh without
    // registering a global key on the owner's Mac.
    delegate.isProcessing = false
    delegate.installedTriggerKey = .f5
    require(guide.onChangeShortcut?("f5") == true && delegate.settingsStore.triggerKey == .f5,
        "Setup shortcut callback did not update the actual settings store")
    require(guide.onReadDetails?().shortcutID == "f5",
        "Setup did not read the newly selected shortcut back from the app")
    require(guide.onChangeShortcut?("unsupported") == false && delegate.settingsStore.triggerKey == .f5,
        "An unsupported setup shortcut changed the app")
    delegate.installedTriggerKey = nil
    delegate.settingsStore.triggerKey = originalShortcut
    delegate.isProcessing = true
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
    guide.present()
    guide.window!.makeFirstResponder(practice)
    spin()
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
    // Exercise the real keyboard-equivalent/responder path. Assigning .string here
    // hid the customer regression: our accessory app had no Edit/Paste command.
    practice.setSelectedRange(NSRange(location: 0, length: (practice.string as NSString).length))
    let stagedPaste = PasteboardInsertionStaging.stage("Every word of this sentence must arrive. ", on: .general)
    let pasteEvent = NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: guide.window!.windowNumber, context: nil,
        characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
    let handledPaste = app.mainMenu?.performKeyEquivalent(with: pasteEvent) == true
    stagedPaste.restoreIfUnchanged(on: .general)
    require(handledPaste && practice.string == "Every word of this sentence must arrive. ",
        "The actual app Command-V route did not paste the complete sentence")
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
}
Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
    runAssertions()
    fflush(stdout)
    app.terminate(nil)
}
app.run()
