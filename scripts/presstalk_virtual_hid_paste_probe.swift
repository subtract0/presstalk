#!/usr/bin/env swift
import Cocoa
import Foundation
import IOKit.hid
import IOKit.hidsystem

private struct Config {
    var payload = "PressTalk virtual HID paste probe"
    var timeout: TimeInterval = 8
    var json = false
}

private final class PasteboardSnapshot {
    let items: [NSPasteboardItem]
    let changeCount: Int

    init(pasteboard: NSPasteboard) {
        changeCount = pasteboard.changeCount
        items = (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    func restore(pasteboard: NSPasteboard) {
        guard pasteboard.changeCount == changeCount + 1 else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}

private final class VirtualHIDPasteProbe: NSObject, NSApplicationDelegate {
    private let config: Config
    private let startedAt = Date()
    private let outputURL: URL
    private let pasteboard = NSPasteboard.general
    private var snapshot: PasteboardSnapshot?
    private var device: IOHIDUserDevice?
    private var window: NSWindow?
    private var textView: NSTextView?
    private var handleReportStatuses: [Int32] = []
    private var deviceCreated = false
    private var finished = false

    init(config: Config) {
        self.config = config
        outputURL = Self.makeOutputURL()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        createWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.runPasteAttempt()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + config.timeout) {
            self.finish(success: false, reason: "timeout_waiting_for_payload")
        }
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PressTalk Virtual HID Paste Probe"
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 220))
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.string = ""
        window.contentView = textView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        self.textView = textView
    }

    private func runPasteAttempt() {
        guard createKeyboardDevice() else {
            finish(success: false, reason: "device_create_failed")
            return
        }
        snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(config.payload, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.sendCommandV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let observed = self.textView?.string ?? ""
                self.finish(
                    success: observed.contains(self.config.payload),
                    reason: observed.contains(self.config.payload) ? "payload_inserted" : "payload_not_observed"
                )
            }
        }
    }

    private func createKeyboardDevice() -> Bool {
        let descriptor = Data([
            0x05, 0x01,       // Usage Page (Generic Desktop)
            0x09, 0x06,       // Usage (Keyboard)
            0xA1, 0x01,       // Collection (Application)
            0x05, 0x07,       // Usage Page (Keyboard)
            0x19, 0xE0,       // Usage Minimum (Keyboard LeftControl)
            0x29, 0xE7,       // Usage Maximum (Keyboard Right GUI)
            0x15, 0x00,       // Logical Minimum (0)
            0x25, 0x01,       // Logical Maximum (1)
            0x75, 0x01,       // Report Size (1)
            0x95, 0x08,       // Report Count (8)
            0x81, 0x02,       // Input (Data, Variable, Absolute)
            0x95, 0x01,       // Report Count (1)
            0x75, 0x08,       // Report Size (8)
            0x81, 0x01,       // Input (Constant)
            0x95, 0x06,       // Report Count (6)
            0x75, 0x08,       // Report Size (8)
            0x15, 0x00,       // Logical Minimum (0)
            0x25, 0x65,       // Logical Maximum (101)
            0x05, 0x07,       // Usage Page (Keyboard)
            0x19, 0x00,       // Usage Minimum (Reserved)
            0x29, 0x65,       // Usage Maximum (Keyboard Application)
            0x81, 0x00,       // Input (Data, Array)
            0xC0              // End Collection
        ])

        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey as String: descriptor as NSData,
            kIOHIDVendorIDKey as String: 0x5054,
            kIOHIDProductIDKey as String: 0x0001,
            kIOHIDVersionNumberKey as String: 1,
            kIOHIDManufacturerKey as String: "PressTalk",
            kIOHIDProductKey as String: "PressTalk Virtual Paste Keyboard",
            kIOHIDPrimaryUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey as String: kHIDUsage_GD_Keyboard,
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]

        guard let created = IOHIDUserDeviceCreateWithProperties(
            kCFAllocatorDefault,
            properties as CFDictionary,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) else {
            return false
        }
        device = created
        deviceCreated = true
        IOHIDUserDeviceSetDispatchQueue(created, DispatchQueue.main)
        IOHIDUserDeviceActivate(created)
        return true
    }

    private func sendCommandV() {
        sendKeyboardReport(modifier: 0x08, key: 0x19)
        Thread.sleep(forTimeInterval: 0.08)
        sendKeyboardReport(modifier: 0x00, key: 0x00)
    }

    private func sendKeyboardReport(modifier: UInt8, key: UInt8) {
        guard let device else { return }
        let report: [UInt8] = [modifier, 0, key, 0, 0, 0, 0, 0]
        let status = report.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let base = rawBuffer.baseAddress else { return kIOReturnBadArgument }
            return IOHIDUserDeviceHandleReportWithTimeStamp(
                device,
                mach_absolute_time(),
                base.assumingMemoryBound(to: UInt8.self),
                report.count
            )
        }
        handleReportStatuses.append(Int32(status))
    }

    private func finish(success: Bool, reason: String) {
        guard !finished else { return }
        finished = true
        let observedText = textView?.string ?? ""
        snapshot?.restore(pasteboard: pasteboard)
        if let device {
            IOHIDUserDeviceCancel(device)
        }
        let payload: [String: Any] = [
            "probeKind": "virtual_hid_paste_probe",
            "probeVersion": 1,
            "generatedAt": iso8601(Date()),
            "durationSeconds": Date().timeIntervalSince(startedAt),
            "success": success,
            "reason": reason,
            "payload": config.payload,
            "observedText": observedText,
            "deviceCreated": deviceCreated,
            "handleReportStatuses": handleReportStatuses,
            "diagnosticPath": outputURL.path
        ]
        writeDiagnostic(payload)
        if config.json {
            printJSON(payload)
        } else {
            print("PressTalk virtual HID paste probe")
            print("Success: \(success)")
            print("Reason: \(reason)")
            print("Observed: \(observedText)")
            print("Diagnostic: \(outputURL.path)")
        }
        NSApp.terminate(nil)
    }

    private func writeDiagnostic(_ payload: [String: Any]) {
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputURL)
        } catch {
            fputs("Diagnostic write failed: \(error)\n", stderr)
        }
    }

    private func printJSON(_ payload: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            print()
        } catch {
            fputs("JSON output failed: \(error)\n", stderr)
        }
    }

    private static func makeOutputURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let stamp = iso8601(Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return home
            .appendingPathComponent("Library/Application Support/JarvisTap/Diagnostics")
            .appendingPathComponent("virtual-hid-paste-probe-\(stamp).json")
    }
}

private func parseConfig() -> Config {
    var config = Config()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--payload":
            if !args.isEmpty { config.payload = args.removeFirst() }
        case "--timeout":
            if !args.isEmpty, let value = Double(args.removeFirst()) { config.timeout = value }
        case "--json":
            config.json = true
        case "-h", "--help":
            print("""
            Usage: presstalk-virtual-hid-paste-probe.swift [--payload TEXT] [--timeout SECONDS] [--json]

            Opens a focused local text window, places TEXT on the pasteboard,
            sends Cmd-V through a temporary IOHIDUserDevice virtual keyboard,
            and records whether the text lands without using Accessibility.
            """)
            exit(0)
        default:
            fputs("Unknown argument: \(arg)\n", stderr)
            exit(2)
        }
    }
    return config
}

private func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private let delegate = VirtualHIDPasteProbe(config: parseConfig())
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
