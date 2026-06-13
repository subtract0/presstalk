import CoreAudio
import Foundation

struct AudioInputDeviceCandidate {
    let id: AudioDeviceID
    let name: String
    let inputChannels: UInt32
    let isDefault: Bool
    let transportType: UInt32?

    var transportDescription: String {
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

    var isBluetoothLike: Bool {
        let lowercasedName = name.lowercased()
        return transportType == kAudioDeviceTransportTypeBluetooth ||
            transportType == kAudioDeviceTransportTypeBluetoothLE ||
            lowercasedName.contains("airpods") ||
            lowercasedName.contains("bluetooth")
    }

    var selectionScore: Int {
        let lowercasedName = name.lowercased()
        var score = 0
        if lowercasedName.contains("shure") { score += 120 }
        if lowercasedName.contains("mv7") { score += 80 }
        if transportType == kAudioDeviceTransportTypeUSB { score += 55 }
        if transportType == kAudioDeviceTransportTypeBuiltIn { score += 20 }
        if transportType == kAudioDeviceTransportTypeVirtual { score -= 15 }
        if lowercasedName.contains("camo") { score -= 20 }
        if lowercasedName.contains("zoom") { score -= 35 }
        if lowercasedName.contains("iphone") { score -= 25 }
        if isBluetoothLike { score -= 140 }
        if isDefault { score += isBluetoothLike ? -40 : 20 }
        score += min(Int(inputChannels), 4)
        return score
    }
}
