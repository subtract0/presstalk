#!/usr/bin/env swift
import AppKit
import Carbon.HIToolbox
import Foundation

final class AutomatedF5SmokeDelegate: NSObject, NSApplicationDelegate {
    private let startedAt = Date()
    private let timeoutSeconds: TimeInterval
    private let minCapturedTextLength: Int
    private let phrase: String
    private let traceLogURL: URL
    private let statusURL: URL
    private let outputURL: URL
    private let initialTraceLineCount: Int
    private let initialRuntimeStatus: [String: Any]?

    private var window: NSWindow!
    private var textView: NSTextView!
    private var statusLabel: NSTextField!
    private var timer: Timer?
    private var completed = false
    private var automationStarted = false
    private var automationFinished = false
    private var automationError: String?
    private var tracePipelineCompletedAt: Date?
    private var traceFinalTranscript: String?
    private var tracePasteCommandPosted = false
    private var traceInserted = false
    private var traceCopyFallback = false
    private var traceNoSpeechAfterRelease = false
    private var traceAudioRMS: Double?
    private var traceAudioPeak: Double?
    private var traceAudioDurationSeconds: Double?
    private var pasteSelfTestResults: [[String: Any]] = []
    private var pasteSelfTestSucceeded = false
    private let pasteSelfTestCases: [(label: String, sourceStateID: CGEventSourceStateID, tap: CGEventTapLocation)] = [
        ("hid_session", .hidSystemState, .cgSessionEventTap),
        ("hid_hid", .hidSystemState, .cghidEventTap),
        ("hid_annotated", .hidSystemState, .cgAnnotatedSessionEventTap),
        ("combined_session", .combinedSessionState, .cgSessionEventTap),
        ("combined_hid", .combinedSessionState, .cghidEventTap),
        ("private_session", .privateState, .cgSessionEventTap),
        ("private_hid", .privateState, .cghidEventTap),
    ]

    override init() {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        timeoutSeconds = env["PRESSTALK_AUTOMATED_SMOKE_TIMEOUT_SECONDS"]
            .flatMap(TimeInterval.init) ?? 60
        minCapturedTextLength = env["PRESSTALK_AUTOMATED_SMOKE_MIN_CAPTURED_TEXT_LENGTH"]
            .flatMap(Int.init) ?? 4
        phrase = env["PRESSTALK_AUTOMATED_SMOKE_PHRASE"] ?? "PressTalk automated smoke test"
        traceLogURL = URL(fileURLWithPath: env["PRESSTALK_TRACE_LOG"] ?? "\(home.path)/Library/Logs/jarvistap_trace.log")
        statusURL = URL(fileURLWithPath: env["PRESSTALK_STATUS_JSON"] ?? "\(home.path)/Library/Application Support/JarvisTap/runtime-status.json")
        initialRuntimeStatus = Self.runtimeStatusDictionary(from: statusURL)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        outputURL = URL(fileURLWithPath: env["PRESSTALK_AUTOMATED_SMOKE_OUTPUT"] ?? "\(home.path)/Library/Application Support/JarvisTap/Diagnostics/automated-f5-smoke-\(stamp).json")

        initialTraceLineCount = Self.traceLines(from: traceLogURL).count
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)

        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.tick()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.runPasteSelfTestCase(at: 0)
        }
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PressTalk Automated F5 Smoke"
        window.center()

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Automated F5 Smoke")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        let instructionLabel = NSTextField(wrappingLabelWithString: "This helper posts the PressTalk F5 bridge notifications, speaks a short phrase through local audio output, and records whether PressTalk pastes text here. It is not physical Fn proof.")
        instructionLabel.font = NSFont.systemFont(ofSize: 13)
        instructionLabel.textColor = .secondaryLabelColor

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.font = NSFont.systemFont(ofSize: 18)
        textView.isEditable = true
        textView.isSelectable = true
        textView.string = ""
        scrollView.documentView = textView

        statusLabel = NSTextField(labelWithString: "Waiting to start. \(Self.readinessSummary(from: initialRuntimeStatus)) Timeout: \(Int(timeoutSeconds)) seconds.")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleLabel, instructionLabel, scrollView, statusLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func focusCaptureWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    private func runPasteSelfTestCase(at index: Int) {
        guard !completed else { return }
        guard index < pasteSelfTestCases.count else {
            textView.string = ""
            focusCaptureWindow()
            statusLabel.stringValue = pasteSelfTestSucceeded
                ? "Paste self-test succeeded. Starting synthetic dictation."
                : "Paste self-test did not capture text. Starting synthetic dictation anyway."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.startAutomation()
            }
            return
        }

        let item = pasteSelfTestCases[index]
        let token = "PT_PASTE_SELF_TEST_\(item.label)_\(UUID().uuidString)"
        textView.string = ""
        focusCaptureWindow()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)

        let postError = Self.postPasteShortcut(sourceStateID: item.sourceStateID, tap: item.tap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            let captured = self.textView.string.contains(token)
            self.pasteSelfTestSucceeded = self.pasteSelfTestSucceeded || captured
            self.pasteSelfTestResults.append([
                "case": item.label,
                "captured": captured,
                "error": postError ?? NSNull(),
                "capturedTextLength": self.textView.string.count,
            ])
            self.runPasteSelfTestCase(at: index + 1)
        }
    }

    private func startAutomation() {
        guard !completed, !automationStarted else { return }
        automationStarted = true

        let triggerKey = Self.stringValue(initialRuntimeStatus, path: ["runtime", "triggerKey"]) ?? "unknown"
        guard triggerKey == "f5" else {
            finish(success: false, reason: "trigger_not_f5", capturedText: textView.string)
            return
        }

        focusCaptureWindow()
        statusLabel.stringValue = "Posting F5 press, speaking phrase, then posting F5 release."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try Self.runProcess("/usr/bin/notifyutil", arguments: ["-p", "com.am.jarvistap.trigger.press"])
                Thread.sleep(forTimeInterval: 0.8)
                try Self.runProcess("/usr/bin/say", arguments: [self.phrase])
                Thread.sleep(forTimeInterval: 0.25)
                DispatchQueue.main.sync {
                    self.focusCaptureWindow()
                }
                Thread.sleep(forTimeInterval: 0.2)
                try Self.runProcess("/usr/bin/notifyutil", arguments: ["-p", "com.am.jarvistap.trigger.release"])
                DispatchQueue.main.async {
                    self.automationFinished = true
                    self.statusLabel.stringValue = "Synthetic trigger released. Waiting for pasted transcript."
                }
            } catch {
                DispatchQueue.main.async {
                    self.automationError = String(describing: error)
                    self.automationFinished = true
                    self.finish(success: false, reason: "automation_error", capturedText: self.textView.string)
                }
            }
        }
    }

    private func tick() {
        guard !completed else { return }
        if automationStarted, !tracePasteCommandPosted {
            focusCaptureWindow()
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        let capturedText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if capturedText.count >= minCapturedTextLength {
            finish(success: true, reason: "captured_text", capturedText: capturedText)
            return
        }

        refreshTracePipelineState()
        if automationFinished, traceNoSpeechAfterRelease {
            finish(
                success: false,
                reason: ttsAudioLikelyNotCaptured ? "tts_audio_not_captured_by_microphone" : "no_speech_captured_after_tts",
                capturedText: capturedText
            )
            return
        }
        if tracePipelineComplete, traceFinalTranscript?.isEmpty == false {
            if tracePipelineCompletedAt == nil {
                tracePipelineCompletedAt = Date()
                statusLabel.stringValue = "PressTalk trace reports transcript and insertion/copy completion. Waiting briefly for target text capture."
            } else if Date().timeIntervalSince(tracePipelineCompletedAt ?? Date()) >= 1.5 {
                finish(success: true, reason: tracePipelineReason, capturedText: capturedText)
                return
            }
        }

        if automationStarted, automationFinished {
            statusLabel.stringValue = "Waiting for pasted transcript. Elapsed: \(Int(elapsed)) / \(Int(timeoutSeconds)) seconds."
        } else if automationStarted {
            statusLabel.stringValue = "Synthetic trigger is recording local speech output. Elapsed: \(Int(elapsed)) / \(Int(timeoutSeconds)) seconds."
        }

        if elapsed >= timeoutSeconds {
            finish(success: false, reason: "timeout", capturedText: capturedText)
        }
    }

    private func refreshTracePipelineState() {
        let traceSinceStart = Array(Self.traceLines(from: traceLogURL).dropFirst(initialTraceLineCount))
        for line in traceSinceStart {
            if let range = line.range(of: "Transkription abgeschlossen:") {
                let transcript = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !transcript.isEmpty {
                    traceFinalTranscript = transcript
                }
            }
            if line.contains("Dictation paste completed") || line.contains("Dictation paste command posted") {
                tracePasteCommandPosted = true
            }
            if line.contains("Dictation inserted method=") {
                traceInserted = true
            }
            if line.contains("Dictation copied because paste unavailable") {
                traceCopyFallback = true
            }
            if line.contains("No speech captured after release") {
                traceNoSpeechAfterRelease = true
            }
            if line.contains("Audio capture frozen") {
                traceAudioDurationSeconds = Self.doubleValue(after: "duration_seconds=", in: line)
                traceAudioRMS = Self.doubleValue(after: "rms=", in: line)
                traceAudioPeak = Self.doubleValue(after: "peak=", in: line)
            }
        }
    }

    private var tracePipelineComplete: Bool {
        tracePasteCommandPosted || traceInserted || traceCopyFallback
    }

    private var tracePipelineReason: String {
        if traceInserted {
            return "trace_pipeline_inserted"
        }
        if tracePasteCommandPosted {
            return "trace_pipeline_command_posted"
        }
        if traceCopyFallback {
            return "trace_pipeline_copy_fallback"
        }
        return "trace_pipeline_incomplete"
    }

    private var ttsAudioLikelyNotCaptured: Bool {
        guard traceNoSpeechAfterRelease else { return false }
        let rms = traceAudioRMS ?? 1
        let peak = traceAudioPeak ?? 1
        return rms < 0.002 && peak < 0.02
    }

    private func finish(success: Bool, reason: String, capturedText: String) {
        guard !completed else { return }
        completed = true
        timer?.invalidate()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let traceLines = Self.traceLines(from: traceLogURL)
        let traceSinceStart = Array(traceLines.dropFirst(initialTraceLineCount).suffix(220))
        let finalRuntimeStatus = Self.runtimeStatusDictionary(from: statusURL)
        refreshTracePipelineState()
        let trimmedCapturedText = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetCaptureSuccess = trimmedCapturedText.count >= minCapturedTextLength
        let targetCaptureFailureHint: Any
        if targetCaptureSuccess {
            targetCaptureFailureHint = NSNull()
        } else if ttsAudioLikelyNotCaptured {
            targetCaptureFailureHint = "tts_output_not_heard_by_microphone"
        } else if traceCopyFallback {
            targetCaptureFailureHint = "accessibility_untrusted_copy_fallback"
        } else if pasteSelfTestSucceeded {
            targetCaptureFailureHint = "target_capture_failed_after_paste_self_test_success"
        } else {
            targetCaptureFailureHint = "local_cmd_v_event_synthesis_unavailable"
        }

        let payload: [String: Any] = [
            "smokeVersion": 1,
            "smokeKind": "automated_f5_darwin_tts",
            "physicalTriggerProof": false,
            "generatedAt": formatter.string(from: Date()),
            "startedAt": formatter.string(from: startedAt),
            "success": success,
            "reason": reason,
            "automationError": automationError ?? NSNull(),
            "spokenPhrase": phrase,
            "capturedText": trimmedCapturedText,
            "targetCaptureSuccess": targetCaptureSuccess,
            "targetCaptureFailureHint": targetCaptureFailureHint,
            "minCapturedTextLength": minCapturedTextLength,
            "pasteSelfTest": [
                "success": pasteSelfTestSucceeded,
                "results": pasteSelfTestResults,
            ],
            "traceFinalTranscript": traceFinalTranscript ?? NSNull(),
            "tracePasteCommandPosted": tracePasteCommandPosted,
            "traceInserted": traceInserted,
            "traceCopyFallback": traceCopyFallback,
            "traceNoSpeechAfterRelease": traceNoSpeechAfterRelease,
            "traceAudioCapture": [
                "durationSeconds": Self.jsonValue(traceAudioDurationSeconds),
                "rms": Self.jsonValue(traceAudioRMS),
                "peak": Self.jsonValue(traceAudioPeak),
                "ttsLikelyNotCapturedByMicrophone": ttsAudioLikelyNotCaptured,
            ],
            "tracePasteCompleted": targetCaptureSuccess,
            "elapsedSeconds": Date().timeIntervalSince(startedAt),
            "expectedTriggerKey": "f5",
            "expectedTriggerLabel": "F5 Darwin notification bridge",
            "readinessAtStart": Self.readinessPayload(from: initialRuntimeStatus),
            "readinessAtFinish": Self.readinessPayload(from: finalRuntimeStatus),
            "traceLogPath": traceLogURL.path,
            "runtimeStatusPath": statusURL.path,
            "runtimeStatusAtStart": initialRuntimeStatus ?? NSNull(),
            "runtimeStatusAtFinish": finalRuntimeStatus ?? NSNull(),
            "traceSinceStart": traceSinceStart,
        ]

        do {
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputURL, options: [.atomic])
            statusLabel.stringValue = success
                ? "Captured pasted text. Result: \(outputURL.path)"
                : "Smoke failed: \(reason). Result: \(outputURL.path)"
            print(outputURL.path)
            fflush(stdout)
        } catch {
            statusLabel.stringValue = "Failed to write result: \(error.localizedDescription)"
            fputs("Failed to write result: \(error)\n", stderr)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 2.5 : 4.0)) {
            NSApp.terminate(nil)
        }
    }

    private static func runProcess(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw SmokeError.processFailed(command: ([launchPath] + arguments).joined(separator: " "), status: process.terminationStatus)
        }
    }

    private static func postPasteShortcut(sourceStateID: CGEventSourceStateID, tap: CGEventTapLocation) -> String? {
        guard let source = CGEventSource(stateID: sourceStateID),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return "event_create_failed"
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: tap)
        keyUp.post(tap: tap)
        return nil
    }

    private static func traceLines(from url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func runtimeStatusDictionary(from url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private static func stringValue(_ dictionary: [String: Any]?, path: [String]) -> String? {
        var current: Any? = dictionary
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        let value = current as? String
        return value?.isEmpty == false ? value : nil
    }

    private static func boolValue(_ dictionary: [String: Any]?, path: [String]) -> Bool? {
        var current: Any? = dictionary
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current as? Bool
    }

    private static func doubleValue(after marker: String, in line: String) -> Double? {
        guard let range = line.range(of: marker) else { return nil }
        let suffix = line[range.upperBound...]
        let token = suffix.prefix { character in
            character.isNumber || character == "." || character == "-"
        }
        return Double(token)
    }

    private static func readinessSummary(from runtimeStatus: [String: Any]?) -> String {
        let pipeline = boolValue(runtimeStatus, path: ["runtime", "inputPipelineReady"]) == true
        let microphone = boolValue(runtimeStatus, path: ["permissions", "microphoneGranted"]) == true
        let microphoneStatus = stringValue(runtimeStatus, path: ["permissions", "microphoneAuthorizationStatus"]) ?? "unknown"
        let speechModel = stringValue(runtimeStatus, path: ["status", "speechModel"]) ?? "unknown"
        let triggerPath = stringValue(runtimeStatus, path: ["status", "triggerPath"]) ?? "unknown"
        return "Ready: mic=\(microphone ? "yes" : "no")(\(microphoneStatus)), input=\(pipeline ? "yes" : "no"), speech=\(speechModel), trigger=\(triggerPath)."
    }

    private static func readinessPayload(from runtimeStatus: [String: Any]?) -> [String: Any] {
        [
            "microphoneGranted": jsonValue(boolValue(runtimeStatus, path: ["permissions", "microphoneGranted"])),
            "microphoneAuthorizationStatus": stringValue(runtimeStatus, path: ["permissions", "microphoneAuthorizationStatus"]) ?? NSNull(),
            "inputMonitoringEffective": jsonValue(boolValue(runtimeStatus, path: ["permissions", "inputMonitoringEffective"])),
            "permissionPaneOpeningAllowed": jsonValue(boolValue(runtimeStatus, path: ["permissions", "permissionPaneOpeningAllowed"])),
            "inputPipelineReady": jsonValue(boolValue(runtimeStatus, path: ["runtime", "inputPipelineReady"])),
            "inputListener": stringValue(runtimeStatus, path: ["runtime", "inputListener"]) ?? NSNull(),
            "speechModel": stringValue(runtimeStatus, path: ["status", "speechModel"]) ?? NSNull(),
            "triggerKey": stringValue(runtimeStatus, path: ["runtime", "triggerKey"]) ?? NSNull(),
            "triggerPath": stringValue(runtimeStatus, path: ["status", "triggerPath"]) ?? NSNull(),
        ]
    }

    private static func jsonValue(_ value: Bool?) -> Any {
        if let value {
            return value
        }
        return NSNull()
    }

    private static func jsonValue(_ value: Double?) -> Any {
        if let value {
            return value
        }
        return NSNull()
    }
}

enum SmokeError: Error {
    case processFailed(command: String, status: Int32)
}

let app = NSApplication.shared
let delegate = AutomatedF5SmokeDelegate()
app.delegate = delegate
app.run()
