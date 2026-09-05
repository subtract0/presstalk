import AppKit
import PressTalkCore

/// The window a new user sees on first launch: one step at a time, each
/// explained in terms of what they get, ending with text they can actually see.
///
/// Deliberately not a wall of switches. macOS grants microphone, input
/// monitoring, and accessibility independently, and asking for all three at once
/// stacks three system dialogs, which is three chances to say no and no
/// explanation of why any of them was needed.
final class FirstRunSetupWindowController: NSWindowController {
    /// Runs the real microphone capture probe. Reported by frames captured, not
    /// by permission status.
    var onVerifyMicrophone: (() -> AudioCaptureProbeReport)?
    var onRequestMicrophoneAccess: ((@escaping (Bool) -> Void) -> Void)?
    var onOpenInputMonitoringSettings: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onReadConditions: (() -> FirstRunSetupPolicy.Conditions)?
    var onDownloadSpeechModel: (() -> Void)?
    var onFinish: (() -> Void)?

    private let policy = FirstRunSetupPolicy()
    private var pollTimer: Timer?
    private var lastProbe: AudioCaptureProbeReport?
    private var skippedSteps: Set<FirstRunSetupPolicy.Step> = []

    private let progressBar = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private let stepTitleLabel = NSTextField(labelWithString: "")
    private let stepBodyLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let primaryButton = NSButton(title: "Continue", target: nil, action: nil)
    private let skipButton = NSButton(title: "Skip for now", target: nil, action: nil)
    private let stepListStack = NSStackView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set up PressTalk"
        window.center()
        super.init(window: window)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "Three permissions, then you dictate.")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)

        let subheading = NSTextField(wrappingLabelWithString:
            "Speech recognition runs on this Mac. Your audio and your text are not uploaded.")
        subheading.textColor = .secondaryLabelColor
        subheading.font = .systemFont(ofSize: 12)

        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.controlSize = .small

        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor

        stepListStack.orientation = .vertical
        stepListStack.alignment = .leading
        stepListStack.spacing = 4

        stepTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        stepBodyLabel.font = .systemFont(ofSize: 12)
        stepBodyLabel.preferredMaxLayoutWidth = 460
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.preferredMaxLayoutWidth = 460

        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped(_:))
        primaryButton.keyEquivalent = "\r"
        skipButton.target = self
        skipButton.action = #selector(skipTapped(_:))
        skipButton.bezelStyle = .inline

        let buttonRow = NSStackView(views: [skipButton, NSView(), primaryButton])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fill

        let stack = NSStackView(views: [
            heading, subheading, progressBar, progressLabel,
            stepListStack, stepTitleLabel, stepBodyLabel, detailLabel, buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            progressBar.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
        ])
    }

    func present() {
        refresh()
        // Permissions are granted in System Settings, in another window. Polling
        // is what lets the step tick over by itself instead of making someone
        // come back and press a button to be told what macOS already knows.
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(finished: Bool) {
        pollTimer?.invalidate()
        pollTimer = nil
        window?.orderOut(nil)
        if finished { onFinish?() }
    }

    private func refresh() {
        guard let base = onReadConditions?() else { return }
        // The window owns the skip decisions; the app only reports the facts.
        let conditions = FirstRunSetupPolicy.Conditions(
            microphoneCaptureVerified: base.microphoneCaptureVerified,
            inputMonitoringGranted: base.inputMonitoringGranted,
            accessibilityGranted: base.accessibilityGranted,
            speechModelReady: base.speechModelReady,
            firstDictationDelivered: base.firstDictationDelivered,
            triggerRequiresInputMonitoring: base.triggerRequiresInputMonitoring,
            skippedSteps: skippedSteps)
        let steps = policy.steps(for: conditions)
        let current = policy.currentStep(for: conditions)

        progressBar.doubleValue = policy.progress(conditions)
        let satisfied = steps.filter { policy.state(of: $0, given: conditions) == .satisfied }.count
        progressLabel.stringValue = "\(satisfied) of \(steps.count) done"

        stepListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for step in steps {
            let done = policy.state(of: step, given: conditions) == .satisfied
            let marker = done ? "✓" : (step == current ? "▸" : "·")
            let row = NSTextField(labelWithString: "\(marker)  \(step.title)")
            row.font = .systemFont(ofSize: 12, weight: step == current ? .semibold : .regular)
            row.textColor = done ? .secondaryLabelColor : .labelColor
            stepListStack.addArrangedSubview(row)
        }

        guard let current else {
            stepTitleLabel.stringValue = "You are set up."
            stepBodyLabel.stringValue = "Hold your trigger key anywhere on this Mac and start talking."
            detailLabel.stringValue = ""
            primaryButton.title = "Done"
            skipButton.isHidden = true
            return
        }

        stepTitleLabel.stringValue = current.title
        stepBodyLabel.stringValue = current.explanation
        skipButton.isHidden = !current.isOptional
        primaryButton.title = primaryButtonTitle(for: current)
        detailLabel.stringValue = detailText(for: current, conditions: conditions)
    }

    private func primaryButtonTitle(for step: FirstRunSetupPolicy.Step) -> String {
        switch step {
        case .microphone: return "Allow microphone"
        case .inputMonitoring: return "Open Input Monitoring settings"
        case .accessibility: return "Open Accessibility settings"
        case .speechModel: return "Download the speech model"
        case .firstDictation: return "I dictated something"
        }
    }

    private func detailText(for step: FirstRunSetupPolicy.Step, conditions: FirstRunSetupPolicy.Conditions) -> String {
        switch step {
        case .microphone:
            guard let probe = lastProbe else { return "" }
            // Says what actually happened, including the case macOS calls
            // "authorized" and no audio arrives.
            return probe.userFacingSummary
        case .inputMonitoring, .accessibility:
            return "Find PressTalk in the list and switch it on. This window updates by itself."
        case .speechModel:
            return conditions.speechModelReady
                ? "Ready."
                : "About 460 MB, downloaded once. Dictation works offline afterwards."
        case .firstDictation:
            return "Open any text field, hold the trigger key, say a short sentence, then let go."
        }
    }

    @objc private func primaryTapped(_ sender: Any?) {
        guard let current = currentStepIncludingSkips() else {
            close(finished: true)
            return
        }

        switch current {
        case .microphone:
            onRequestMicrophoneAccess? { [weak self] _ in
                DispatchQueue.main.async {
                    // Granting is not the same as working, so verify by capture.
                    self?.lastProbe = self?.onVerifyMicrophone?()
                    self?.refresh()
                }
            }
        case .inputMonitoring:
            onOpenInputMonitoringSettings?()
        case .accessibility:
            onOpenAccessibilitySettings?()
        case .speechModel:
            onDownloadSpeechModel?()
        case .firstDictation:
            refresh()
        }
    }

    @objc private func skipTapped(_ sender: Any?) {
        guard let current = currentStepIncludingSkips(), current.isOptional else { return }
        // Recorded, not just announced. Changing the label without recording the
        // choice left the same step selected, so "Skip for now" did nothing.
        skippedSteps.insert(current)
        refresh()
        detailLabel.stringValue =
            "Skipped. PressTalk will copy dictated text to the clipboard so you can paste it yourself."
    }

    private func currentStepIncludingSkips() -> FirstRunSetupPolicy.Step? {
        guard let base = onReadConditions?() else { return nil }
        return policy.currentStep(for: FirstRunSetupPolicy.Conditions(
            microphoneCaptureVerified: base.microphoneCaptureVerified,
            inputMonitoringGranted: base.inputMonitoringGranted,
            accessibilityGranted: base.accessibilityGranted,
            speechModelReady: base.speechModelReady,
            firstDictationDelivered: base.firstDictationDelivered,
            triggerRequiresInputMonitoring: base.triggerRequiresInputMonitoring,
            skippedSteps: skippedSteps))
    }
}
