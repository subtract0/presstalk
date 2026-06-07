#!/usr/bin/env swift
import AppKit
import Foundation

private let notificationName = "com.am.presstalk.production-insertion-probe.insert"
private let payloadFileName = "production-insertion-probe.txt"

private struct Options {
    var payload = "PressTalk production insertion probe"
    var timeoutSeconds: TimeInterval = 10.0
    var json = false
}

private func parseOptions() -> Options {
    var options = Options()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--payload":
            guard let value = iterator.next(), !value.isEmpty else {
                fputs("Missing value for --payload\n", stderr)
                exit(2)
            }
            options.payload = value
        case "--timeout":
            guard let value = iterator.next(), let seconds = Double(value), seconds > 0 else {
                fputs("Invalid value for --timeout\n", stderr)
                exit(2)
            }
            options.timeoutSeconds = seconds
        case "--json":
            options.json = true
        case "--help", "-h":
            print("""
            Usage: presstalk-production-insertion-probe.swift [--payload TEXT] [--timeout SECONDS] [--json]

            Opens a focused local text window, asks the already-running
            PressTalk app to insert a payload through its production insertion
            path, and records whether text lands. The running app must have
            PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE=1.
            """)
            exit(0)
        default:
            fputs("Unknown argument: \(argument)\n", stderr)
            exit(2)
        }
    }
    return options
}

private func supportDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/JarvisTap", isDirectory: true)
}

private func diagnosticsDirectory() -> URL {
    supportDirectory().appendingPathComponent("Diagnostics", isDirectory: true)
}

private func payloadURL() -> URL {
    supportDirectory().appendingPathComponent(payloadFileName)
}

private func traceLogURL() -> URL {
    URL(fileURLWithPath: ProcessInfo.processInfo.environment["PRESSTALK_TRACE_LOG"] ??
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Logs/jarvistap_trace.log")
}

private func statusURL() -> URL {
    URL(fileURLWithPath: ProcessInfo.processInfo.environment["PRESSTALK_STATUS_JSON"] ??
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/JarvisTap/runtime-status.json")
}

private func traceLines(from url: URL) -> [String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

private func runtimeStatusDictionary(from url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
    return object as? [String: Any]
}

private func emitJSON(_ payload: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8) ?? "{}")
    } catch {
        fputs("Failed to serialize JSON: \(error)\n", stderr)
        exit(1)
    }
}

private func stringValue(_ dictionary: [String: Any]?, path: [String]) -> String? {
    var current: Any? = dictionary
    for key in path {
        current = (current as? [String: Any])?[key]
    }
    let value = current as? String
    return value?.isEmpty == false ? value : nil
}

private func boolValue(_ dictionary: [String: Any]?, path: [String]) -> Bool? {
    var current: Any? = dictionary
    for key in path {
        current = (current as? [String: Any])?[key]
    }
    return current as? Bool
}

private func jsonValue(_ value: Bool?) -> Any {
    value ?? NSNull()
}

private func readinessPayload(from runtimeStatus: [String: Any]?) -> [String: Any] {
    [
        "bundleIdentifier": stringValue(runtimeStatus, path: ["app", "bundleIdentifier"]) ?? NSNull(),
        "microphoneAuthorizationStatus": stringValue(runtimeStatus, path: ["permissions", "microphoneAuthorizationStatus"]) ?? NSNull(),
        "inputMonitoringEffective": jsonValue(boolValue(runtimeStatus, path: ["permissions", "inputMonitoringEffective"])),
        "accessibilityStatus": stringValue(runtimeStatus, path: ["permissions", "accessibilityStatus"]) ?? NSNull(),
        "inputMethodFallbackStatus": stringValue(runtimeStatus, path: ["permissions", "inputMethodFallbackStatus"]) ?? NSNull(),
        "inputPipelineReady": jsonValue(boolValue(runtimeStatus, path: ["runtime", "inputPipelineReady"])),
        "inputListener": stringValue(runtimeStatus, path: ["runtime", "inputListener"]) ?? NSNull(),
        "activeFieldInsertionReady": jsonValue(boolValue(runtimeStatus, path: ["runtime", "activeFieldInsertionReady"])),
        "activeFieldInsertionStatus": stringValue(runtimeStatus, path: ["runtime", "activeFieldInsertionStatus"]) ?? NSNull(),
        "speechModel": stringValue(runtimeStatus, path: ["status", "speechModel"]) ?? NSNull(),
        "triggerPath": stringValue(runtimeStatus, path: ["status", "triggerPath"]) ?? NSNull(),
        "adHocSigned": jsonValue(boolValue(runtimeStatus, path: ["status", "adHocSigned"])),
        "codeSignatureCDHash": stringValue(runtimeStatus, path: ["status", "codeSignatureCDHash"]) ?? NSNull(),
    ]
}

private final class ProductionInsertionProbeDelegate: NSObject, NSApplicationDelegate {
    private let options: Options
    private let startedAt = Date()
    private let traceURL = traceLogURL()
    private let runtimeURL = statusURL()
    private let initialTraceLineCount: Int
    private let initialRuntimeStatus: [String: Any]?
    private let outputURL: URL

    private var window: NSWindow?
    private var textView: NSTextView?
    private var timer: Timer?
    private var didPost = false
    private var didFinish = false
    private var traceNotificationInstalled = false
    private var traceNotificationReceived = false
    private var traceInserted = false
    private var tracePasteCommandPosted = false
    private var traceCopyFallback = false
    private var traceInputMethodEnableNoEffect = false
    private var traceInputMethodSelectFailed = false
    private var traceInputMethodFailure: String?
    private var traceProductionFailure: String?
    private var traceProductionMethod: String?
    private var targetCaptureDetectedAt: Date?

    init(options: Options) {
        self.options = options
        initialTraceLineCount = traceLines(from: traceURL).count
        initialRuntimeStatus = runtimeStatusDictionary(from: runtimeURL)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        outputURL = diagnosticsDirectory().appendingPathComponent("production-insertion-probe-\(stamp).json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        openProbeWindow()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.postProbeRequest()
        }
    }

    private func openProbeWindow() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 220))
        textView.isEditable = true
        textView.isSelectable = true
        textView.string = ""
        textView.font = NSFont.systemFont(ofSize: 18)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 220))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 220),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PressTalk Production Insertion Probe"
        window.center()
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.textView = textView
    }

    private func focusProbeWindow() {
        guard let window, let textView else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    private func postProbeRequest() {
        guard !didPost else { return }
        didPost = true
        focusProbeWindow()

        do {
            try FileManager.default.createDirectory(at: supportDirectory(), withIntermediateDirectories: true)
            try options.payload.write(to: payloadURL(), atomically: true, encoding: .utf8)
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(notificationName as CFString),
                nil,
                nil,
                true
            )
        } catch {
            finish(success: false, reason: "post_probe_failed: \(error)")
        }
    }

    private func refreshTraceState() {
        let lines = Array(traceLines(from: traceURL).dropFirst(initialTraceLineCount))
        for line in lines {
            if line.contains("Production insertion probe notification installed") {
                traceNotificationInstalled = true
            }
            if line.contains("Production insertion probe notification received") {
                traceNotificationReceived = true
            }
            if let range = line.range(of: "Production insertion probe inserted method=") {
                traceInserted = true
                traceProductionMethod = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if line.contains("Production insertion probe paste command posted") {
                tracePasteCommandPosted = true
            }
            if let range = line.range(of: "Production insertion probe copied fallback reason=") {
                traceCopyFallback = true
                traceProductionFailure = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let range = line.range(of: "Production insertion probe failed error=") {
                traceProductionFailure = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let range = line.range(of: "Input method insertion unavailable reason=") {
                traceInputMethodFailure = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if line.contains("reason=enable_no_effect") {
                    traceInputMethodEnableNoEffect = true
                }
                if line.contains("reason=select_failed") {
                    traceInputMethodSelectFailed = true
                }
            }
        }
        if traceNotificationReceived || traceInserted || tracePasteCommandPosted || traceCopyFallback || traceProductionFailure != nil || traceInputMethodFailure != nil {
            traceNotificationInstalled = true
            traceNotificationReceived = true
        }
    }

    private func tick() {
        guard !didFinish else { return }
        refreshTraceState()

        let capturedText = textView?.string ?? ""
        if capturedText.contains(options.payload) {
            if targetCaptureDetectedAt == nil {
                targetCaptureDetectedAt = Date()
            }
            if Date().timeIntervalSince(targetCaptureDetectedAt ?? Date()) >= 1.2 {
                finish(success: true, reason: "payload_inserted")
            }
            return
        }

        if Date().timeIntervalSince(startedAt) >= options.timeoutSeconds {
            finish(success: false, reason: "timeout_waiting_for_payload")
        }
    }

    private func writeDiagnostics(_ payload: [String: Any]) -> String {
        do {
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputURL, options: .atomic)
            return outputURL.path
        } catch {
            return "write_failed: \(error)"
        }
    }

    private func finish(success: Bool, reason: String) {
        guard !didFinish else { return }
        didFinish = true
        timer?.invalidate()
        refreshTraceState()

        let finalRuntimeStatus = runtimeStatusDictionary(from: runtimeURL)
        let traceSinceStart = Array(traceLines(from: traceURL).dropFirst(initialTraceLineCount).suffix(160))
        let capturedText = textView?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetCaptureSuccess = capturedText.contains(options.payload)
        let targetCaptureFailureHint: Any
        if targetCaptureSuccess {
            targetCaptureFailureHint = NSNull()
        } else if !traceNotificationInstalled {
            targetCaptureFailureHint = "production_probe_not_enabled"
        } else if !traceNotificationReceived {
            targetCaptureFailureHint = "production_probe_notification_not_received"
        } else if traceInputMethodEnableNoEffect {
            targetCaptureFailureHint = "input_method_enable_no_effect"
        } else if traceInputMethodSelectFailed {
            targetCaptureFailureHint = "input_method_select_failed"
        } else if traceCopyFallback {
            targetCaptureFailureHint = "production_probe_copy_fallback"
        } else if traceInserted {
            targetCaptureFailureHint = "target_capture_failed_after_production_insert_trace"
        } else if tracePasteCommandPosted {
            targetCaptureFailureHint = "target_capture_failed_after_paste_command_trace"
        } else {
            targetCaptureFailureHint = NSNull()
        }

        var payload: [String: Any] = [
            "probeVersion": 1,
            "probeKind": "production_insertion_probe",
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "success": success,
            "reason": reason,
            "payload": options.payload,
            "observedText": capturedText,
            "targetCaptureSuccess": targetCaptureSuccess,
            "targetCaptureFailureHint": targetCaptureFailureHint,
            "notification": notificationName,
            "payloadFile": payloadURL().path,
            "timeoutSeconds": options.timeoutSeconds,
            "durationSeconds": Date().timeIntervalSince(startedAt),
            "readinessAtStart": readinessPayload(from: initialRuntimeStatus),
            "readinessAtFinish": readinessPayload(from: finalRuntimeStatus),
            "traceNotificationInstalled": traceNotificationInstalled,
            "traceNotificationReceived": traceNotificationReceived,
            "traceInserted": traceInserted,
            "tracePasteCommandPosted": tracePasteCommandPosted,
            "traceCopyFallback": traceCopyFallback,
            "traceProductionMethod": traceProductionMethod ?? NSNull(),
            "traceProductionFailure": traceProductionFailure ?? NSNull(),
            "traceInputMethodEnableNoEffect": traceInputMethodEnableNoEffect,
            "traceInputMethodSelectFailed": traceInputMethodSelectFailed,
            "traceInputMethodFailure": traceInputMethodFailure ?? NSNull(),
            "traceLogPath": traceURL.path,
            "runtimeStatusPath": runtimeURL.path,
            "traceSinceStart": traceSinceStart,
        ]
        payload["diagnosticPath"] = writeDiagnostics(payload)

        window?.close()
        if options.json {
            emitJSON(payload)
        } else {
            print("PressTalk production insertion probe")
            print("Success: \(success)")
            print("Reason: \(reason)")
            print("Diagnostic: \(payload["diagnosticPath"] ?? "unknown")")
        }
        NSApp.terminate(nil)
    }
}

private let options = parseOptions()
private let app = NSApplication.shared
private let delegate = ProductionInsertionProbeDelegate(options: options)
app.delegate = delegate
app.run()
