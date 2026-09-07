import CoreAudio
import Foundation

public struct AudioInputDeviceCandidate {
    public let id: AudioDeviceID
    public let name: String
    public let inputChannels: UInt32
    public let isDefault: Bool
    public let transportType: UInt32?
    /// Stable across reboots and replugs, unlike `id`, so this is what a saved
    /// preference stores.
    public let uid: String

    public init(
        id: AudioDeviceID,
        name: String,
        inputChannels: UInt32,
        isDefault: Bool,
        transportType: UInt32?,
        uid: String = ""
    ) {
        self.id = id
        self.name = name
        self.inputChannels = inputChannels
        self.isDefault = isDefault
        self.transportType = transportType
        self.uid = uid.isEmpty ? "device-\(id)" : uid
    }

    public var transportDescription: String {
        guard let transportType else { return "unknown" }
        switch transportType {
        case kAudioDeviceTransportTypeUSB:
            return "usb"
        case kAudioDeviceTransportTypeBluetooth:
            return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "bluetooth_le"
        case kAudioDeviceTransportTypeBuiltIn:
            return "built_in"
        case kAudioDeviceTransportTypeVirtual:
            return "virtual"
        default:
            return "\(transportType)"
        }
    }

    public var isBluetoothLike: Bool {
        let lowercasedName = name.lowercased()
        return transportType == kAudioDeviceTransportTypeBluetooth ||
            transportType == kAudioDeviceTransportTypeBluetoothLE ||
            lowercasedName.contains("bluetooth")
    }

    public var isVirtualLike: Bool {
        transportType == kAudioDeviceTransportTypeVirtual
    }

    /// An iPhone or iPad offered as a microphone over Continuity.
    ///
    /// Neither wired nor built-in in any sense that matters to a person: it is
    /// a phone, it may be in another room or another pocket, and it stops being
    /// a microphone the moment someone picks it up. It was being counted as a
    /// physical alternative and could therefore be chosen over the actual
    /// built-in microphone -- with an iPhone 17 sitting on the desk, which is
    /// exactly the hardware this was first reported on.
    /// Transport type only. This also matched the names "iphone" and "ipad",
    /// which the capture-lifecycle check rejects and is right to: hard-coding
    /// one person's hardware into the selector is how a table of local
    /// opinions ends up shipping. CoreAudio labels these devices itself, and
    /// the label is the correct signal.
    public var isContinuityLike: Bool {
        transportType == kAudioDeviceTransportTypeContinuityCaptureWired
            || transportType == kAudioDeviceTransportTypeContinuityCaptureWireless
    }

    public var isPhysicalInput: Bool {
        !isBluetoothLike && !isVirtualLike && !isContinuityLike
    }

    /// Ranks devices when the user has asked PressTalk to avoid Bluetooth and
    /// more than one alternative exists.
    ///
    /// This used to run unconditionally, which meant a table of one person's
    /// hardware opinions silently overruled the microphone every user had
    /// already chosen in System Settings. It is now reached only through
    /// `AudioInputPreference.preferWired` -- which IS the default as of
    /// 2026-09-07, so the ranking is load-bearing again and the comment
    /// claiming otherwise was wrong within a day of being written.
    ///
    /// The scores are hardware categories, not measured latency, and that
    /// limit is real: a fast desk microphone is the wrong answer for someone
    /// speaking into a headset across the room. What the ranking is for is
    /// avoiding a wireless device's 1.2 s wake-up when a wired one is sitting
    /// right there, and it never overrides a device the person chose by name.
    public var selectionScore: Int {
        var score = 0
        // Built-in ABOVE USB, which is the reverse of what this said first.
        //
        // A USB audio interface reports its channels whether or not a
        // microphone is plugged into them, and nothing in CoreAudio's metadata
        // distinguishes a live capsule from an empty input. An idle interface
        // on the desk scored 57 against the built-in microphone's 21 and won,
        // so the automatic choice could land on a device that returns silence.
        //
        // The built-in microphone cannot be silently absent. It is also the
        // fallback the owner named -- "AirPods should never be on by default if
        // the user has a built-in microphone" -- and the whole purpose of this
        // ranking is escaping Bluetooth's wake-up cost, which built-in does
        // completely. Whether a USB podcast microphone sounds better is a
        // judgement this code cannot make from metadata; the person can make it
        // once in Settings, where it is remembered and overrides all of this.
        if transportType == kAudioDeviceTransportTypeBuiltIn { score += 55 }
        if transportType == kAudioDeviceTransportTypeUSB { score += 35 }
        if isVirtualLike { score -= 15 }
        if isBluetoothLike { score -= 140 }
        // Below every real microphone but above nothing at all: usable when it
        // is genuinely the only input, never preferred over one attached to
        // the Mac.
        if isContinuityLike { score -= 120 }
        if isDefault { score += isBluetoothLike ? -40 : 20 }
        score += min(Int(inputChannels), 4)
        return score
    }

    public var selectorDevice: AudioInputSelector.Device {
        .init(uid: uid, name: name, isDefault: isDefault,
              isBluetooth: isBluetoothLike, isVirtual: isVirtualLike,
              isContinuity: isContinuityLike)
    }
}
