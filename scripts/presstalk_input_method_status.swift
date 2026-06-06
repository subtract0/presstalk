#!/usr/bin/env swift
import Carbon
import Foundation

private let inputMethodSourceID = "com.am.presstalk.inputmethod"
private let inputModeSourceID = inputMethodSourceID
private let bundleIdentifier = "com.am.presstalk.inputmethod"
private let appName = "PressTalkInputMethod.app"

private struct Options {
    var register = false
    var enable = false
    var select = false
    var json = false
}

private func parseOptions() -> Options {
    var options = Options()
    for argument in CommandLine.arguments.dropFirst() {
        switch argument {
        case "--register":
            options.register = true
        case "--enable":
            options.enable = true
        case "--select":
            options.select = true
        case "--json":
            options.json = true
        case "--help", "-h":
            print("""
            Usage: presstalk-input-method-status.swift [--register] [--enable] [--select] [--json]

            Default mode is read-only. It reports whether macOS recognizes the
            PressTalk input method and which input source is currently selected.

            --register  Register ~/Library/Input Methods/PressTalkInputMethod.app
            --enable    Enable com.am.presstalk.inputmethod if macOS recognizes it
            --select    Select com.am.presstalk.inputmethod if it is enabled
            --json      Emit machine-readable JSON
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

private func currentInputSourceSummary() -> [String: Any] {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    return sourceSummary(source)
}

private func printJSON(_ payload: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8) ?? "{}")
    } catch {
        fputs("Failed to serialize JSON: \(error)\n", stderr)
        exit(1)
    }
}

private func printHuman(_ payload: [String: Any]) {
    print("PressTalk Input Method Status")
    print("Installed bundle: \(payload["installedBundlePath"] ?? "unknown")")
    print("Installed bundle exists: \(payload["installedBundleExists"] ?? false)")
    print("Current input source: \(payload["currentInputSourceID"] ?? "unknown")")
    print("Recognized source count: \(payload["recognizedSourceCount"] ?? 0)")
    print("Recognized enabled source count: \(payload["recognizedEnabledSourceCount"] ?? 0)")
    print("Recognized all-installed source count: \(payload["recognizedAllSourceCount"] ?? 0)")
    print("Register status: \(payload["registerStatus"] ?? "not_requested")")
    print("Enable status: \(payload["enableStatus"] ?? "not_requested")")
    print("Select status: \(payload["selectStatus"] ?? "not_requested")")

    guard let sources = payload["sources"] as? [[String: Any]], !sources.isEmpty else {
        return
    }

    for source in sources {
        print("")
        print("Source: \(source["id"] ?? "unknown")")
        print("  name: \(source["localizedName"] ?? "unknown")")
        print("  bundleID: \(source["bundleID"] ?? "unknown")")
        print("  type: \(source["type"] ?? "unknown")")
        print("  category: \(source["category"] ?? "unknown")")
        print("  enabled: \(source["enabled"] ?? "unknown")")
        print("  selectCapable: \(source["selectCapable"] ?? "unknown")")
        print("  selected: \(source["selected"] ?? "unknown")")
    }
}

private let options = parseOptions()
private let bundleURL = installedBundleURL()
private let installedBundleExists = FileManager.default.fileExists(atPath: bundleURL.path)

private var registerStatus: Any = "not_requested"
if options.register {
    if !installedBundleExists {
        registerStatus = "bundle_missing"
        fputs("Cannot register missing bundle: \(bundleURL.path)\n", stderr)
    } else {
        registerStatus = Int(TISRegisterInputSource(bundleURL as CFURL))
    }
}

private var enabledSources = findPressTalkSources(includeAllInstalled: false)
private var allSources = findPressTalkSources(includeAllInstalled: true)
private var enableStatus: Any = "not_requested"
if options.enable {
    if allSources.isEmpty {
        enableStatus = "source_not_recognized"
    } else {
        let source = preferredSelectableSource(from: allSources) ?? allSources[0]
        enableStatus = Int(TISEnableInputSource(source))
        enabledSources = findPressTalkSources(includeAllInstalled: false)
        allSources = findPressTalkSources(includeAllInstalled: true)
    }
}

private var selectStatus: Any = "not_requested"
if options.select {
    if enabledSources.isEmpty {
        selectStatus = allSources.isEmpty ? "source_not_recognized" : "source_not_enabled"
    } else {
        let source = preferredSelectableSource(from: enabledSources) ?? enabledSources[0]
        selectStatus = Int(TISSelectInputSource(source))
        enabledSources = findPressTalkSources(includeAllInstalled: false)
        allSources = findPressTalkSources(includeAllInstalled: true)
    }
}

private let current = currentInputSourceSummary()
private let payload: [String: Any] = [
    "installedBundlePath": bundleURL.path,
    "installedBundleExists": installedBundleExists,
    "inputMethodSourceID": inputMethodSourceID,
    "inputModeSourceID": inputModeSourceID,
    "currentInputSourceID": current["id"] ?? NSNull(),
    "currentInputSource": current,
    "recognizedSourceCount": allSources.count,
    "recognizedEnabledSourceCount": enabledSources.count,
    "recognizedAllSourceCount": allSources.count,
    "enabledSources": enabledSources.map(sourceSummary),
    "sources": allSources.map(sourceSummary),
    "registerStatus": registerStatus,
    "enableStatus": enableStatus,
    "selectStatus": selectStatus,
]

if options.json {
    printJSON(payload)
} else {
    printHuman(payload)
}
