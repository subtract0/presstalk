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

    public var isPhysicalInput: Bool {
        !isBluetoothLike && !isVirtualLike
    }

    /// Ranks devices when the user has asked PressTalk to avoid Bluetooth and
    /// more than one alternative exists.
    ///
    /// This used to run unconditionally, which meant a table of one person's
    /// hardware opinions silently overruled the microphone every user had
    /// already chosen in System Settings. It is now reached only through
    /// `AudioInputPreference.preferWired`, which nobody gets by default.
    public var selectionScore: Int {
        var score = 0
        if transportType == kAudioDeviceTransportTypeUSB { score += 55 }
        if transportType == kAudioDeviceTransportTypeBuiltIn { score += 20 }
        if isVirtualLike { score -= 15 }
        if isBluetoothLike { score -= 140 }
        if isDefault { score += isBluetoothLike ? -40 : 20 }
        score += min(Int(inputChannels), 4)
        return score
    }

    public var selectorDevice: AudioInputSelector.Device {
        .init(uid: uid, name: name, isDefault: isDefault,
              isBluetooth: isBluetoothLike, isVirtual: isVirtualLike)
    }
}
