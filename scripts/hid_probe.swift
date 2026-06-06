import Foundation
import IOKit.hid

private struct ProbeState {
    let start = Date()
    let timeout: TimeInterval
}

private func propertyString(_ device: IOHIDDevice, key: CFString) -> String {
    guard let value = IOHIDDeviceGetProperty(device, key) else { return "?" }
    return String(describing: value)
}

private func nowString(from start: Date) -> String {
    String(format: "%.3f", Date().timeIntervalSince(start))
}

private func usageName(page: UInt32, usage: UInt32) -> String {
    switch (page, usage) {
    case (UInt32(kHIDPage_Consumer), UInt32(kHIDUsage_Csmr_Microphone)):
        return "consumer.microphone"
    case (UInt32(kHIDPage_Consumer), UInt32(kHIDUsage_Csmr_VoiceCommand)):
        return "consumer.voice_command"
    case (UInt32(kHIDPage_Consumer), UInt32(kHIDUsage_Csmr_PlayOrPause)):
        return "consumer.play_or_pause"
    case (UInt32(kHIDPage_KeyboardOrKeypad), 0x3E):
        return "keyboard.f5"
    default:
        return "page_0x" + String(page, radix: 16) + ".usage_0x" + String(usage, radix: 16)
    }
}

private let interestedPages: Set<UInt32> = [
    UInt32(kHIDPage_KeyboardOrKeypad),
    UInt32(kHIDPage_Consumer),
]

private let state = ProbeState(timeout: 20)
private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    let product = propertyString(device, key: kIOHIDProductKey as CFString)
    let transport = propertyString(device, key: kIOHIDTransportKey as CFString)
    let vendor = propertyString(device, key: kIOHIDVendorIDKey as CFString)
    let productID = propertyString(device, key: kIOHIDProductIDKey as CFString)
    print("[device] product=\(product) transport=\(transport) vendor=\(vendor) product_id=\(productID)")
    fflush(stdout)
}, nil)

IOHIDManagerRegisterInputValueCallback(manager, { context, _, sender, value in
    guard let context, let sender else { return }

    let state = Unmanaged<AnyObject>.fromOpaque(context).takeUnretainedValue() as! ProbeBox
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    guard interestedPages.contains(page) else { return }

    let intValue = IOHIDValueGetIntegerValue(value)
    if intValue == 0 && page != UInt32(kHIDPage_Consumer) {
        return
    }

    let device = unsafeBitCast(sender, to: IOHIDDevice.self)
    let product = propertyString(device, key: kIOHIDProductKey as CFString)
    let transport = propertyString(device, key: kIOHIDTransportKey as CFString)
    let vendor = propertyString(device, key: kIOHIDVendorIDKey as CFString)
    let productID = propertyString(device, key: kIOHIDProductIDKey as CFString)
    let name = usageName(page: page, usage: usage)
    print("[\(nowString(from: state.start))] page=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16)) value=\(intValue) name=\(name) product=\(product) transport=\(transport) vendor=\(vendor) product_id=\(productID)")
    fflush(stdout)
}, Unmanaged.passUnretained(ProbeBox(start: state.start)).toOpaque())

final class ProbeBox: NSObject {
    let start: Date
    init(start: Date) {
        self.start = start
    }
}

let matching: [[String: Any]] = [
    [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ],
    [
        kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
        kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl,
    ],
]

IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    fputs("Failed to open IOHIDManager: \(openResult)\n", stderr)
    exit(1)
}

print("Listening for HID values for \(Int(state.timeout)) seconds. Press Fn/Globe, Option, F5, or click the trackpad.")
fflush(stdout)

DispatchQueue.main.asyncAfter(deadline: .now() + state.timeout) {
    print("Probe finished.")
    fflush(stdout)
    CFRunLoopStop(CFRunLoopGetCurrent())
}

CFRunLoopRun()
