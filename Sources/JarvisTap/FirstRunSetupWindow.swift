import AppKit
import PressTalkCore

private final class SetupDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// A check ends with a real dictation, and every action shows what happens next.
final class FirstRunSetupWindowController: NSWindowController, NSWindowDelegate {
    enum ModelState { case idle, loading, ready, failed }
    struct ShortcutChoice: Equatable {
        let id: String
        let title: String
    }
    struct Details {
        var microphoneAuthorization = "not_determined"
        var microphoneName = "Selected microphone"
        var triggerName = "your trigger key"
        var shortcutID = ""
        var shortcutChoices: [ShortcutChoice] = []
        var modelState: ModelState = .idle
        var modelStatus = ""
        var recordingOrProcessing = false
        var isRecording = false
        var pasteAutomatically = true
        var shortcutUsesRegisteredHotKey = false
    }

    var onVerifyMicrophone: ((@escaping (AudioCaptureProbeReport) -> Void) -> Void)?
    var onRequestMicrophoneAccess: ((@escaping (Bool) -> Void) -> Void)?
    var onOpenMicrophoneSettings: (() -> Void)?
    var onOpenInputMonitoringSettings: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onRetryShortcut: (() -> Bool)?
    var onChangeShortcut: ((String) -> Bool)?
    var onReadConditions: (() -> FirstRunSetupPolicy.Conditions)?
    var onReadDetails: (() -> Details)?
    var onDownloadSpeechModel: (() -> Void)?
    var onConfirmDictation: (() -> Void)?
    var onFinish: (() -> Void)?

    private let policy = FirstRunSetupPolicy()
    private var pollTimer: Timer?
    private var lastProbe: AudioCaptureProbeReport?
    private var microphoneMessage = ""
    private var shortcutMessage = ""
    private var shortcutChangeMessage = ""
    private var checkingMicrophone = false
    private var expectedDictation: String?
    private var practiceBeforeDictation = ""
    private var practiceSelectionBeforeDictation = NSRange(location: 0, length: 0)
    private var confirmedDictation = false
    private var skippedSteps: Set<FirstRunSetupPolicy.Step> = []
    private let shortcutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let shortcutHint = NSTextField(wrappingLabelWithString: "")
    private var shortcutChoices: [ShortcutChoice] = []
    private let progressLabel = NSTextField(labelWithString: "")
    private let stepTitleLabel = NSTextField(labelWithString: "")
    private let stepBodyLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let primaryButton = NSButton(title: "Continue", target: nil, action: nil)
    private let skipButton = NSButton(title: "Use clipboard instead", target: nil, action: nil)
    private let stepListStack = NSStackView()
    private let practiceScrollView = NSScrollView()
    private let practiceTextView = NSTextView()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 610),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Set up PressTalk"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 480)
        window.center()
        super.init(window: window)
        window.delegate = self
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }
        let heading = NSTextField(labelWithString: "Let’s check your dictation setup.")
        heading.font = .systemFont(ofSize: 19, weight: .semibold)
        let subheading = NSTextField(wrappingLabelWithString:
            "Check your microphone and shortcut, then dictate a sentence. Your audio and text stay on this Mac.")
        subheading.textColor = .secondaryLabelColor
        subheading.font = .systemFont(ofSize: 12)
        let shortcutLabel = NSTextField(labelWithString: "Hold to dictate")
        shortcutLabel.font = .systemFont(ofSize: 13, weight: .medium)
        shortcutPopup.setAccessibilityIdentifier("setup.shortcut")
        shortcutPopup.setAccessibilityLabel("Dictation shortcut")
        shortcutPopup.target = self
        shortcutPopup.action = #selector(shortcutChanged(_:))
        let shortcutRow = NSStackView(views: [shortcutLabel, shortcutPopup])
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 12
        shortcutHint.font = .systemFont(ofSize: 12)
        shortcutHint.textColor = .secondaryLabelColor
        shortcutHint.setAccessibilityIdentifier("setup.shortcutHint")
        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.setAccessibilityIdentifier("setup.progress")
        stepListStack.orientation = .vertical
        stepListStack.alignment = .leading
        stepListStack.spacing = 4
        stepTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        stepTitleLabel.setAccessibilityIdentifier("setup.step")
        stepBodyLabel.font = .systemFont(ofSize: 13)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.setAccessibilityIdentifier("setup.detail")
        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped(_:))
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.setAccessibilityIdentifier("setup.primary")
        skipButton.target = self
        skipButton.action = #selector(skipTapped(_:))
        skipButton.bezelStyle = .inline
        skipButton.setAccessibilityIdentifier("setup.skip")
        practiceTextView.isRichText = false
        practiceTextView.font = .systemFont(ofSize: 14)
        practiceTextView.textContainerInset = NSSize(width: 10, height: 10)
        practiceTextView.isHorizontallyResizable = false
        practiceTextView.isVerticallyResizable = true
        practiceTextView.autoresizingMask = [.width]
        practiceTextView.textContainer?.widthTracksTextView = true
        practiceTextView.setAccessibilityIdentifier("setup.practice")
        practiceTextView.setAccessibilityLabel("Try dictation here")
        practiceScrollView.documentView = practiceTextView
        practiceScrollView.hasVerticalScroller = true
        practiceScrollView.borderType = .bezelBorder
        practiceScrollView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        let buttonRow = NSStackView(views: [skipButton, NSView(), primaryButton])
        buttonRow.orientation = .horizontal
        // Keep the next action ahead of already-satisfied checks. A percentage
        // bar looked like background work even while we were waiting for a click.
        let stack = NSStackView(views: [heading, subheading, shortcutRow, shortcutHint,
            stepTitleLabel, stepBodyLabel, detailLabel, practiceScrollView, buttonRow,
            progressLabel, stepListStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for field in [subheading, shortcutHint, stepBodyLabel, detailLabel] {
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            field.cell?.isScrollable = false
            field.cell?.usesSingleLineMode = false
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        for view in [subheading, shortcutHint, stepBodyLabel, detailLabel, practiceScrollView, buttonRow] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let document = SetupDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        contentView.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
        ])
    }

    func present() {
        expectedDictation = nil
        confirmedDictation = false
        refresh()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func beginDictation() {
        practiceBeforeDictation = practiceTextView.string
        practiceSelectionBeforeDictation = practiceTextView.selectedRange()
        expectedDictation = nil
    }

    func observeDictation(_ transcript: String) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        expectedDictation = text
        refresh()
    }

    private func confirmDictation() {
        guard !confirmedDictation else { return }
        confirmedDictation = true
        onConfirmDictation?()
    }

    func close(finished: Bool) {
        pollTimer?.invalidate()
        pollTimer = nil
        window?.orderOut(nil)
        if finished { onFinish?() }
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func conditions() -> FirstRunSetupPolicy.Conditions? {
        guard let base = onReadConditions?() else { return nil }
        return .init(microphoneCaptureVerified: base.microphoneCaptureVerified,
            inputMonitoringGranted: base.inputMonitoringGranted,
            accessibilityGranted: base.accessibilityGranted, speechModelReady: base.speechModelReady,
            firstDictationDelivered: base.firstDictationDelivered,
            triggerRequiresInputMonitoring: base.triggerRequiresInputMonitoring,
            triggerRequiresAccessibility: base.triggerRequiresAccessibility, skippedSteps: skippedSteps)
    }

    /// Also used by the AppKit interaction tests with real controls and isolated state.
    func refresh() {
        if let expectedDictation, newlyInsertedPracticeText()?.contains(expectedDictation) == true {
            confirmDictation()
        }
        guard let conditions = conditions(), let details = onReadDetails?() else {
            detailLabel.stringValue = "Setup could not read the app’s status. Close this window and try again."
            primaryButton.isEnabled = false
            return
        }
        let steps = policy.steps(for: conditions)
        let current = policy.currentStep(for: conditions)
        if shortcutChoices != details.shortcutChoices {
            shortcutChoices = details.shortcutChoices
            shortcutPopup.removeAllItems()
            shortcutPopup.addItems(withTitles: shortcutChoices.map(\.title))
        }
        if let index = shortcutChoices.firstIndex(where: { $0.id == details.shortcutID }) {
            shortcutPopup.selectItem(at: index)
        }
        shortcutPopup.isEnabled = !details.recordingOrProcessing && !checkingMicrophone
        shortcutHint.stringValue = shortcutChangeMessage.isEmpty
            ? "If Fn / Globe does nothing on your keyboard, choose Option + Space or F5 here. You’ll try it below."
            : shortcutChangeMessage
        if conditions.inputMonitoringGranted { shortcutMessage = "" }
        let resolved = steps.filter {
            let state = policy.state(of: $0, given: conditions)
            return state == .satisfied || state == .skipped
        }.count
        progressLabel.stringValue = "\(resolved) of \(steps.count) checks complete"
        stepListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for step in steps {
            let state = policy.state(of: step, given: conditions)
            let marker = state == .satisfied ? "✓" : (state == .skipped ? "–" : (step == current ? "▸" : "·"))
            let suffix = state == .skipped ? " (using clipboard)" : ""
            let row = NSTextField(labelWithString: "\(marker)  \(step.title)\(suffix)")
            row.font = .systemFont(ofSize: 12, weight: step == current ? .semibold : .regular)
            stepListStack.addArrangedSubview(row)
        }
        primaryButton.isEnabled = !checkingMicrophone
        skipButton.isHidden = current.map { !policy.canSkip($0, given: conditions) } ?? true
        practiceScrollView.isHidden = current != .firstDictation && current != nil
        guard let current else {
            stepTitleLabel.stringValue = "Your dictation setup works."
            stepBodyLabel.stringValue = "You have captured audio and delivered a dictation. Hold \(details.triggerName) in any text field to keep going."
            detailLabel.stringValue = details.pasteAutomatically && conditions.accessibilityGranted
                ? "Your text is inserted automatically."
                : "Your text is copied to the clipboard. Press ⌘V to paste it."
            primaryButton.title = "Done"
            return
        }
        stepTitleLabel.stringValue = current.title
        stepBodyLabel.stringValue = current.explanation
        switch current {
        case .microphone:
            stepBodyLabel.stringValue = "Click Test microphone, then speak for a moment into \(details.microphoneName)."
            if checkingMicrophone {
                primaryButton.title = "Checking microphone…"
                stepBodyLabel.stringValue = "Checking \(details.microphoneName)…"
                detailLabel.stringValue = "Speak normally for a moment. This check stays on your Mac and is not saved."
            } else if details.recordingOrProcessing {
                primaryButton.title = "Test microphone"
                primaryButton.isEnabled = false
                detailLabel.stringValue = "Finish your current dictation first. The microphone check will then be available."
            } else {
                switch details.microphoneAuthorization {
                case "denied", "restricted":
                    primaryButton.title = "Open Microphone Settings"
                    stepBodyLabel.stringValue = "Click Open Microphone Settings to allow access to \(details.microphoneName)."
                    detailLabel.stringValue = "Microphone access is off. Enable PressTalk in Microphone Settings, then return here to test it."
                    return
                case "authorized": primaryButton.title = "Test microphone"
                default: primaryButton.title = "Allow microphone"
                }
                if details.microphoneAuthorization != "authorized" {
                    stepBodyLabel.stringValue = "Click Allow microphone and approve the macOS prompt. Then speak for a moment into \(details.microphoneName)."
                }
                detailLabel.stringValue = microphoneMessage.isEmpty
                    ? (lastProbe.flatMap { $0.isUsable ? nil : $0.userFacingSummary }
                        ?? "Waiting for you to click. Nothing is recording yet. This checks your selected microphone without changing your Mac’s default input.")
                    : microphoneMessage
            }
        case .accessibility:
            primaryButton.title = "Open Accessibility Settings"
            if conditions.triggerRequiresAccessibility {
                stepBodyLabel.stringValue = "Your \(details.triggerName) shortcut needs Accessibility permission so PressTalk can respond to the key. It also lets PressTalk insert text into other apps."
            }
            detailLabel.stringValue = permissionInstructions
        case .inputMonitoring:
            primaryButton.title = details.shortcutUsesRegisteredHotKey
                ? "Retry shortcut" : "Open Input Monitoring Settings"
            detailLabel.stringValue = details.shortcutUsesRegisteredHotKey
                ? (shortcutMessage.isEmpty
                    ? "PressTalk could not register this shortcut. Retry it, or choose a different shortcut above if another app uses it."
                    : shortcutMessage)
                : permissionInstructions
        case .speechModel:
            switch details.modelState {
            case .idle: primaryButton.title = "Prepare speech model"
            case .loading:
                primaryButton.title = "Preparing speech model…"
                primaryButton.isEnabled = false
            case .failed: primaryButton.title = "Retry speech model"
            case .ready: primaryButton.title = "Check model status"
            }
            detailLabel.stringValue = details.modelStatus.isEmpty
                ? "The first run may need a model download. Once prepared, speech recognition works offline."
                : details.modelStatus
        case .firstDictation:
            primaryButton.title = expectedDictation == nil ? "Try dictation here" : "Confirm full sentence"
            stepBodyLabel.stringValue = "Click the box below, hold \(details.triggerName), say a sentence, and release. You can also use a text field in another app."
            if details.recordingOrProcessing {
                primaryButton.isEnabled = false
                primaryButton.title = details.isRecording ? "Listening…" : "Recognising…"
                detailLabel.stringValue = details.isRecording
                    ? "Speak your sentence, then release \(details.triggerName)."
                    : "Your recording has ended. Wait for the recognised sentence to appear."
            } else if expectedDictation != nil {
                detailLabel.stringValue = "A sentence was recognised. If you used this box, paste with ⌘V if needed. If you used another app, confirm only after checking that the whole sentence appeared there."
            } else {
                detailLabel.stringValue = details.pasteAutomatically && conditions.accessibilityGranted
                    ? "Waiting for you to hold \(details.triggerName). If nothing happens, choose another shortcut above. The full recognised sentence must appear here; typing alone does not complete the check."
                    : "After dictating, press ⌘V to paste the copied words."
            }
        }
    }

    @objc private func shortcutChanged(_ sender: NSPopUpButton) {
        guard let details = onReadDetails?(), !details.recordingOrProcessing,
              !checkingMicrophone, shortcutChoices.indices.contains(sender.indexOfSelectedItem) else {
            refresh()
            return
        }
        let changed = onChangeShortcut?(shortcutChoices[sender.indexOfSelectedItem].id) ?? false
        shortcutChangeMessage = changed ? "" : "The shortcut could not be changed. Finish any current dictation and try again."
        refresh()
    }

    private func newlyInsertedPracticeText() -> String? {
        let before = practiceBeforeDictation as NSString
        let after = practiceTextView.string as NSString
        let selection = practiceSelectionBeforeDictation
        guard after != before, selection.location != NSNotFound,
              NSMaxRange(selection) <= before.length else { return nil }
        let prefix = before.substring(to: selection.location)
        let suffix = before.substring(from: NSMaxRange(selection))
        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length
        guard after.length >= prefixLength + suffixLength,
              (prefix.isEmpty || after.hasPrefix(prefix)),
              (suffix.isEmpty || after.hasSuffix(suffix)) else { return nil }
        // Check only the new insertion. An old matching sentence elsewhere in
        // the field cannot compensate for a missing or truncated new paste.
        return after.substring(with: NSRange(location: prefixLength,
            length: after.length - prefixLength - suffixLength))
    }

    private var permissionInstructions: String {
        "Enable PressTalk in System Settings, then return here. This window checks automatically. If PressTalk is missing, use + to add this copy: \(Bundle.main.bundleURL.path)."
    }

    @objc private func primaryTapped(_ sender: Any?) {
        guard let conditions = conditions(), let details = onReadDetails?() else { return }
        guard let current = policy.currentStep(for: conditions) else {
            close(finished: true)
            return
        }
        switch current {
        case .microphone:
            guard !checkingMicrophone, !details.recordingOrProcessing else { return }
            if ["denied", "restricted"].contains(details.microphoneAuthorization) {
                onOpenMicrophoneSettings?()
                return
            }
            checkingMicrophone = true
            microphoneMessage = ""
            lastProbe = nil
            refresh()
            if details.microphoneAuthorization == "authorized" {
                verifyMicrophone()
            } else {
                onRequestMicrophoneAccess? { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if granted { self.verifyMicrophone() }
                        else {
                            self.checkingMicrophone = false
                            self.microphoneMessage = "Microphone access wasn’t granted. Enable PressTalk in Microphone Settings, then try again."
                            self.refresh()
                        }
                    }
                }
            }
        case .inputMonitoring:
            if details.shortcutUsesRegisteredHotKey {
                let ready = onRetryShortcut?() ?? false
                shortcutMessage = ready ? "Shortcut is ready."
                    : "The shortcut is still unavailable. Choose another shortcut above, then try again."
                refresh()
            } else { onOpenInputMonitoringSettings?() }
        case .accessibility: onOpenAccessibilitySettings?()
        case .speechModel:
            onDownloadSpeechModel?()
            refresh()
        case .firstDictation:
            if expectedDictation != nil { confirmDictation(); refresh() }
            else { window?.makeFirstResponder(practiceTextView) }
        }
    }

    private func verifyMicrophone() {
        onVerifyMicrophone? { [weak self] report in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastProbe = report
                self.checkingMicrophone = false
                self.refresh()
            }
        }
    }

    @objc private func skipTapped(_ sender: Any?) {
        guard let conditions = conditions(), let current = policy.currentStep(for: conditions),
              policy.canSkip(current, given: conditions) else { return }
        skippedSteps.insert(current)
        refresh()
    }
}
