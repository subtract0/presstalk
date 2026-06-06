#!/usr/bin/env swift
import AppKit
import Carbon
import Foundation

private let inputMethodSourceID = "com.am.presstalk.inputmethod"
private let inputModeSourceID = "com.am.presstalk.inputmethod.dictation"
private let bundleIdentifier = "com.am.presstalk.inputmethod"
private let appName = "PressTalkInputMethod.app"
private let notificationName = "com.am.presstalk.inputmethod.insert"

private struct Options {
    var payload = "PressTalk input method client probe"
    var timeoutSeconds: TimeInterval = 8.0
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
            Usage: presstalk-input-method-client-probe.swift [--payload TEXT] [--timeout SECONDS] [--json]

            Opens a temporary local text view, temporarily selects the PressTalk
            input method, posts the PressTalk insert notification, verifies
            whether the payload appears in the focused text view, then restores
            the original input source. It does not open System Settings.
            """)
            exit(0)
        default:
            fputs("Unknown argument: \(argument)\n", stderr)
            exit(2)
        }
    }
    return options
}

private func property(_ source: TISInputSource, _ key: CFString) -> Any? {
    guard let unmanaged = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(unmanaged).takeUnretainedValue()
}

private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    property(source, key) as? String
}

private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
    guard let value = property(source, key) else { return nil }
    if let bool = value as? Bool {
        return bool
    }
    if let number = value as? NSNumber {
        return number.boolValue
    }
    return nil
}

private func sourceSummary(_ source: TISInputSource) -> [String: Any] {
    [
        "id": stringProperty(source, kTISPropertyInputSourceID) ?? NSNull(),
        "bundleID": stringProperty(source, kTISPropertyBundleID) ?? NSNull(),
        "localizedName": stringProperty(source, kTISPropertyLocalizedName) ?? NSNull(),
        "category": stringProperty(source, kTISPropertyInputSourceCategory) ?? NSNull(),
        "type": stringProperty(source, kTISPropertyInputSourceType) ?? NSNull(),
        "enabled": boolProperty(source, kTISPropertyInputSourceIsEnabled) ?? NSNull(),
        "enableCapable": boolProperty(source, kTISPropertyInputSourceIsEnableCapable) ?? NSNull(),
        "selectCapable": boolProperty(source, kTISPropertyInputSourceIsSelectCapable) ?? NSNull(),
        "selected": boolProperty(source, kTISPropertyInputSourceIsSelected) ?? NSNull(),
    ]
}

private func sourceKey(_ source: TISInputSource) -> String {
    let id = stringProperty(source, kTISPropertyInputSourceID)
    let bundleID = stringProperty(source, kTISPropertyBundleID)
    return [id, bundleID].compactMap { $0 }.joined(separator: "|")
}

private func findPressTalkSources(includeAllInstalled: Bool) -> [TISInputSource] {
    func createList(_ properties: [CFString: Any]) -> [Any] {
        guard let list = TISCreateInputSourceList(properties as CFDictionary, includeAllInstalled) else {
            return []
        }
        return list.takeRetainedValue() as NSArray as Array
    }

    let byMethodID = createList([kTISPropertyInputSourceID: inputMethodSourceID])
    let byModeID = createList([kTISPropertyInputSourceID: inputModeSourceID])
    let byBundle = createList([kTISPropertyBundleID: bundleIdentifier])

    var sources: [TISInputSource] = []
    var seen = Set<String>()
    for object in byMethodID + byModeID + byBundle {
        guard CFGetTypeID(object as CFTypeRef) == TISInputSourceGetTypeID() else { continue }
        let source = object as! TISInputSource
        let key = sourceKey(source)
        let fallbackKey = "\(Unmanaged.passUnretained(source).toOpaque())"
        let uniqueKey = key.isEmpty ? fallbackKey : key
        guard !seen.contains(uniqueKey) else { continue }
        seen.insert(uniqueKey)
        sources.append(source)
    }
    return sources
}

private func preferredSelectableSource(from sources: [TISInputSource]) -> TISInputSource? {
    sources.first {
        stringProperty($0, kTISPropertyInputSourceID) == inputModeSourceID &&
            (boolProperty($0, kTISPropertyInputSourceIsSelectCapable) ?? true)
    } ?? sources.first {
        boolProperty($0, kTISPropertyInputSourceIsSelectCapable) ?? false
    } ?? sources.first
}

private func installedBundleURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Input Methods", isDirectory: true)
        .appendingPathComponent(appName)
}

private func supportDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/JarvisTap", isDirectory: true)
}

private func diagnosticsDirectory() -> URL {
    supportDirectory().appendingPathComponent("Diagnostics", isDirectory: true)
}

private func payloadURL() -> URL {
    supportDirectory().appendingPathComponent("input-method-insert.txt")
}

private func inputMethodLogURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/presstalk_input_method.log")
}

private func tailLines(url: URL, maxLines: Int) -> [String] {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
        return []
    }
    return Array(content.split(whereSeparator: \.isNewline).suffix(maxLines).map(String.init))
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

private final class ClientProbeApp: NSObject, NSApplicationDelegate {
    private let options: Options
    private let originalSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var window: NSWindow?
    private var textView: NSTextView?
    private var startedAt = Date()
    private var timer: Timer?
    private var didFinish = false
    private var registerStatus: Any = "not_requested"
    private var enableStatus: Any = "not_requested"
    private var selectStatus: Any = "not_requested"
    private var restoreStatus: Any = "not_requested"
    private var disableStatus: Any = "not_requested"
    private var wasEnabledBeforeProbe = false
    private var pressTalkSourceBeforeProbe: [String: Any] = [:]

    init(options: Options) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startedAt = Date()
        NSApp.setActivationPolicy(.regular)

        guard prepareInputMethod() else {
            finish(success: false, reason: "input_method_not_selectable")
            return
        }

        openProbeWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.armTextClient()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.postInsertNotification()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.pollForResult()
        }
    }

    private func prepareInputMethod() -> Bool {
        let bundleURL = installedBundleURL()
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            registerStatus = "bundle_missing"
            return false
        }

        registerStatus = Int(TISRegisterInputSource(bundleURL as CFURL))

        let enabledBefore = findPressTalkSources(includeAllInstalled: false)
        wasEnabledBeforeProbe = !enabledBefore.isEmpty

        var allSources = findPressTalkSources(includeAllInstalled: true)
        guard let allSource = preferredSelectableSource(from: allSources) ?? allSources.first else {
            return false
        }
        pressTalkSourceBeforeProbe = sourceSummary(allSource)

        if enabledBefore.isEmpty {
            enableStatus = Int(TISEnableInputSource(allSource))
        } else {
            enableStatus = "already_enabled"
        }

        let enabledSources = findPressTalkSources(includeAllInstalled: false)
        guard let enabledSource = preferredSelectableSource(from: enabledSources) ?? enabledSources.first else {
            return false
        }
        selectStatus = Int(TISSelectInputSource(enabledSource))

        allSources = findPressTalkSources(includeAllInstalled: true)
        if let selected = allSources.first(where: { boolProperty($0, kTISPropertyInputSourceIsSelected) == true }),
           stringProperty(selected, kTISPropertyInputSourceID) == inputModeSourceID {
            return true
        }

        return Int("\(selectStatus)") == 0
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
        window.title = "PressTalk Input Method Probe"
        window.center()
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.textView = textView
    }

    private func armTextClient() {
        guard let textView, let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)

        if let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ) {
            _ = textView.inputContext?.handleEvent(event)
        }
        textView.string = ""
    }

    private func postInsertNotification() {
        do {
            try FileManager.default.createDirectory(
                at: supportDirectory(),
                withIntermediateDirectories: true
            )
            try options.payload.write(to: payloadURL(), atomically: true, encoding: .utf8)
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(notificationName as CFString),
                nil,
                nil,
                true
            )
        } catch {
            finish(success: false, reason: "write_payload_failed: \(error)")
        }
    }

    private func pollForResult() {
        guard !didFinish else { return }
        let currentText = textView?.string ?? ""
        if currentText.contains(options.payload) {
            finish(success: true, reason: "payload_inserted")
            return
        }

        if Date().timeIntervalSince(startedAt) >= options.timeoutSeconds {
            finish(success: false, reason: "timeout_waiting_for_payload")
        }
    }

    private func restoreInputSource() {
        restoreStatus = Int(TISSelectInputSource(originalSource))
        if !wasEnabledBeforeProbe {
            if let source = findPressTalkSources(includeAllInstalled: true).first {
                disableStatus = Int(TISDisableInputSource(source))
            } else {
                disableStatus = "source_not_found"
            }
        } else {
            disableStatus = "left_enabled_original_state"
        }
    }

    private func writeDiagnostics(_ payload: [String: Any]) -> String {
        do {
            try FileManager.default.createDirectory(
                at: diagnosticsDirectory(),
                withIntermediateDirectories: true
            )
            let stamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: ".", with: "-")
            let url = diagnosticsDirectory()
                .appendingPathComponent("input-method-client-probe-\(stamp).json")
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
        restoreInputSource()

        let currentSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        var payload: [String: Any] = [
            "success": success,
            "reason": reason,
            "payload": options.payload,
            "observedText": textView?.string ?? "",
            "timeoutSeconds": options.timeoutSeconds,
            "durationSeconds": Date().timeIntervalSince(startedAt),
            "notification": notificationName,
            "payloadFile": payloadURL().path,
            "installedBundlePath": installedBundleURL().path,
            "pressTalkSourceBeforeProbe": pressTalkSourceBeforeProbe,
            "pressTalkWasEnabledBeforeProbe": wasEnabledBeforeProbe,
            "registerStatus": registerStatus,
            "enableStatus": enableStatus,
            "selectStatus": selectStatus,
            "restoreStatus": restoreStatus,
            "disableStatus": disableStatus,
            "originalInputSource": sourceSummary(originalSource),
            "finalInputSource": sourceSummary(currentSource),
            "inputMethodLogTail": tailLines(url: inputMethodLogURL(), maxLines: 30),
        ]
        payload["diagnosticPath"] = writeDiagnostics(payload)

        window?.close()
        if options.json {
            emitJSON(payload)
        } else {
            print("PressTalk input method client probe")
            print("Success: \(success)")
            print("Reason: \(reason)")
            print("Diagnostic: \(payload["diagnosticPath"] ?? "unknown")")
            print("Original input source: \(sourceSummary(originalSource)["id"] ?? "unknown")")
            print("Final input source: \(sourceSummary(currentSource)["id"] ?? "unknown")")
            print("Observed text: \(payload["observedText"] ?? "")")
        }
        NSApp.terminate(nil)
    }
}

private let options = parseOptions()
private let app = NSApplication.shared
private let delegate = ClientProbeApp(options: options)
app.delegate = delegate
app.run()
