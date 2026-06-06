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

            Opens a local text view, posts Unicode CGEvent key events, and
            reports whether the payload lands. It does not open System Settings.
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
    private var timer: Timer?
    private var didFinish = false
    private var postResult = "not_posted"

    init(options: Options) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        openProbeWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.postPayload()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.poll()
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

    private func postPayload() {
        guard let window, let textView else {
            postResult = "no_target_window"
            return
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            postResult = "event_synthesis_unavailable"
            return
        }

        for codeUnit in options.payload.utf16 {
            var unit = codeUnit
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            keyDown.flags = []
            keyUp.flags = []
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        postResult = "posted"
    }

    private func poll() {
        guard !didFinish else { return }
        let observed = textView?.string ?? ""
        if observed.contains(options.payload) {
            finish(success: true, reason: "payload_inserted")
            return
        }
        if Date().timeIntervalSince(startedAt) >= options.timeoutSeconds {
            finish(success: false, reason: "timeout_waiting_for_payload")
        }
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
        timer?.invalidate()

        var payload: [String: Any] = [
            "success": success,
            "reason": reason,
            "payload": options.payload,
            "observedText": textView?.string ?? "",
            "postResult": postResult,
            "accessibilityTrusted": AXIsProcessTrusted(),
            "durationSeconds": Date().timeIntervalSince(startedAt),
            "timeoutSeconds": options.timeoutSeconds,
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
            print("Observed text: \(payload["observedText"] ?? "")")
        }
        NSApp.terminate(nil)
    }
}

private let options = parseOptions()
private let app = NSApplication.shared
private let delegate = UnicodeEventProbeApp(options: options)
app.delegate = delegate
app.run()
