#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

private struct Options {
    var payload = "PressTalk unicode event probe"
    var timeoutSeconds: TimeInterval = 3.0
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
            Usage: presstalk-unicode-event-insert-probe.swift [--payload TEXT] [--timeout SECONDS] [--json]

            Opens a local text view, posts Unicode CGEvent key events through
            several delivery paths, and reports whether the payload lands. It
            does not open System Settings.
            """)
            exit(0)
        default:
            fputs("Unknown argument: \(argument)\n", stderr)
            exit(2)
        }
    }
    return options
}

private func diagnosticsDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/JarvisTap/Diagnostics", isDirectory: true)
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

private final class UnicodeEventProbeApp: NSObject, NSApplicationDelegate {
    private let options: Options
    private let startedAt = Date()
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var window: NSWindow?
    private var textView: NSTextView?
    private var didFinish = false
    private var postResult = "not_started"
    private var methodResults: [[String: Any]] = []
    private let postMethods = ["hid", "session", "annotated", "pid"]
    private var methodIndex = 0

    init(options: Options) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        openProbeWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.runNextMethod()
        }
    }

    private func openProbeWindow() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 180))
        textView.isEditable = true
        textView.isSelectable = true
        textView.string = ""
        textView.font = NSFont.systemFont(ofSize: 18)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 180))
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PressTalk Unicode Event Probe"
        window.center()
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.textView = textView
    }

    private func runNextMethod() {
        guard !didFinish else { return }
        guard methodIndex < postMethods.count else {
            let succeeded = methodResults.contains { result in
                (result["success"] as? Bool) == true
            }
            finish(success: succeeded, reason: succeeded ? "payload_inserted" : "timeout_waiting_for_payload")
            return
        }

        let method = postMethods[methodIndex]
        methodIndex += 1
        textView?.string = ""

        guard let window, let textView else {
            postResult = "no_target_window"
            methodResults.append([
                "method": method,
                "postResult": postResult,
                "observedText": "",
                "success": false,
            ])
            runNextMethod()
            return
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)

        let posted = postPayload(method: method, targetPID: getpid())
        DispatchQueue.main.asyncAfter(deadline: .now() + perMethodTimeoutSeconds) { [weak self] in
            guard let self else { return }
            let observed = textView.string
            let success = observed.contains(self.options.payload)
            self.methodResults.append([
                "method": method,
                "postResult": posted,
                "observedText": observed,
                "success": success,
            ])
            self.runNextMethod()
        }
    }

    private var perMethodTimeoutSeconds: TimeInterval {
        max(0.25, options.timeoutSeconds / Double(max(postMethods.count, 1)))
    }

    private func postPayload(method: String, targetPID: pid_t) -> String {
        for codeUnit in options.payload.utf16 {
            var unit = codeUnit
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                postResult = "event_synthesis_unavailable"
                return postResult
            }

            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            keyDown.flags = []
            keyUp.flags = []

            switch method {
            case "hid":
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            case "session":
                keyDown.post(tap: .cgSessionEventTap)
                keyUp.post(tap: .cgSessionEventTap)
            case "annotated":
                keyDown.post(tap: .cgAnnotatedSessionEventTap)
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            case "pid":
                keyDown.postToPid(targetPID)
                keyUp.postToPid(targetPID)
            default:
                postResult = "unknown_method"
                return postResult
            }
        }

        postResult = "posted"
        return postResult
    }

    private func writeDiagnostics(_ payload: [String: Any]) -> String {
        do {
            try FileManager.default.createDirectory(at: diagnosticsDirectory(), withIntermediateDirectories: true)
            let stamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: ".", with: "-")
            let url = diagnosticsDirectory().appendingPathComponent("unicode-event-insert-probe-\(stamp).json")
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return "write_failed: \(error)"
        }
    }

    private func finish(success: Bool, reason: String) {
        guard !didFinish else { return }
        didFinish = true

        var payload: [String: Any] = [
            "success": success,
            "reason": reason,
            "payload": options.payload,
            "observedText": textView?.string ?? "",
            "postResult": postResult,
            "methodResults": methodResults,
            "targetProcessID": getpid(),
            "accessibilityTrusted": AXIsProcessTrusted(),
            "durationSeconds": Date().timeIntervalSince(startedAt),
            "timeoutSeconds": options.timeoutSeconds,
            "perMethodTimeoutSeconds": perMethodTimeoutSeconds,
        ]
        payload["diagnosticPath"] = writeDiagnostics(payload)

        window?.close()
        if options.json {
            emitJSON(payload)
        } else {
            print("PressTalk Unicode event insertion probe")
            print("Success: \(success)")
            print("Reason: \(reason)")
            print("Post result: \(postResult)")
            print("Accessibility trusted: \(AXIsProcessTrusted())")
            print("Diagnostic: \(payload["diagnosticPath"] ?? "unknown")")
            for result in methodResults {
                print("Method \(result["method"] ?? "unknown"): success=\(result["success"] ?? false) post=\(result["postResult"] ?? "unknown") observed=\(result["observedText"] ?? "")")
            }
        }
        NSApp.terminate(nil)
    }
}

private let options = parseOptions()
private let app = NSApplication.shared
private let delegate = UnicodeEventProbeApp(options: options)
app.delegate = delegate
app.run()
