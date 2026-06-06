#!/usr/bin/env swift
import AppKit
import Foundation

final class ManualFnSmokeDelegate: NSObject, NSApplicationDelegate {
    private let startedAt = Date()
    private let timeoutSeconds: TimeInterval
    private let traceLogURL: URL
    private let statusURL: URL
    private let outputURL: URL
    private let initialTraceLineCount: Int

    private var window: NSWindow!
    private var textView: NSTextView!
    private var statusLabel: NSTextField!
    private var timer: Timer?
    private var completed = false

    override init() {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        timeoutSeconds = env["PRESSTALK_MANUAL_SMOKE_TIMEOUT_SECONDS"]
            .flatMap(TimeInterval.init) ?? 90
        traceLogURL = URL(fileURLWithPath: env["PRESSTALK_TRACE_LOG"] ?? "\(home.path)/Library/Logs/jarvistap_trace.log")
        statusURL = URL(fileURLWithPath: env["PRESSTALK_STATUS_JSON"] ?? "\(home.path)/Library/Application Support/JarvisTap/runtime-status.json")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        outputURL = URL(fileURLWithPath: env["PRESSTALK_MANUAL_SMOKE_OUTPUT"] ?? "\(home.path)/Library/Application Support/JarvisTap/Diagnostics/manual-fn-smoke-\(stamp).json")

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
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PressTalk Manual Fn Smoke"
        window.center()

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Physical Fn / Globe Smoke")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        let instructionLabel = NSTextField(wrappingLabelWithString: "Click the empty box below, hold Fn / Globe, say a short sentence such as 'PressTalk smoke test', then release. This window records whether text is pasted here.")
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

        statusLabel = NSTextField(labelWithString: "Waiting for pasted text. Timeout: \(Int(timeoutSeconds)) seconds.")
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

    private func tick() {
        guard !completed else { return }

        let elapsed = Date().timeIntervalSince(startedAt)
        let capturedText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !capturedText.isEmpty {
            finish(success: true, reason: "captured_text", capturedText: capturedText)
            return
        }

        statusLabel.stringValue = "Waiting for pasted text. Elapsed: \(Int(elapsed)) / \(Int(timeoutSeconds)) seconds."
        if elapsed >= timeoutSeconds {
            finish(success: false, reason: "timeout", capturedText: capturedText)
        }
    }

    private func finish(success: Bool, reason: String, capturedText: String) {
        completed = true
        timer?.invalidate()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let traceLines = Self.traceLines(from: traceLogURL)
        let traceSinceStart = Array(traceLines.dropFirst(initialTraceLineCount).suffix(160))

        let payload: [String: Any] = [
            "generatedAt": formatter.string(from: Date()),
            "startedAt": formatter.string(from: startedAt),
            "success": success,
            "reason": reason,
            "capturedText": capturedText,
            "elapsedSeconds": Date().timeIntervalSince(startedAt),
            "traceLogPath": traceLogURL.path,
            "runtimeStatusPath": statusURL.path,
            "runtimeStatus": Self.runtimeStatus(from: statusURL) ?? NSNull(),
            "traceSinceStart": traceSinceStart,
        ]

        do {
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputURL, options: [.atomic])
            statusLabel.stringValue = success
                ? "Captured pasted text. Result: \(outputURL.path)"
                : "Timed out. Result: \(outputURL.path)"
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

    private static func traceLines(from url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func runtimeStatus(from url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

let app = NSApplication.shared
let delegate = ManualFnSmokeDelegate()
app.delegate = delegate
app.run()
